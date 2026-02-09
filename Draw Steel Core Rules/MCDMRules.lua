local mod = dmhub.GetModLoading()


--this resets the game rules, allowing us to start from scratch and define our system.
GameSystem.ClearRules()

--what this game system calls things.
GameSystem.HitpointsName = "Stamina"
GameSystem.AttributeName = "Characteristic"
GameSystem.AttributeNamePlural = "Characteristics"
GameSystem.SkillName = "Skill"
GameSystem.SkillNamePlural = "Skills"
GameSystem.SavingThrowName = "Resistance"
GameSystem.SavingThrowRollName = "Reactive Test"
GameSystem.SavingThrowNamePlural = "Resistances"

GameSystem.BackgroundName = "Career"
GameSystem.BackgroundNamePlural = "Careers"
GameSystem.RaceName = "Ancestry"
GameSystem.RaceNamePlural = "Ancestries"
GameSystem.RacesHaveHeights = false
GameSystem.CRName = "LVL"
GameSystem.ChallengeName = "Level"
GameSystem.ChallengeRatingName = "Level"

--what the basic rolls look like in our system.
GameSystem.BaseAttackRoll = "2d10"
GameSystem.BaseSkillRoll = "2d10"
GameSystem.BaseSavingThrowRoll = "2d10"
GameSystem.FlatRoll = "2d10"

--do critical hits modify damage in this game system?
GameSystem.CriticalHitsModifyDamage = false

--start of round is an important trigger.
GameSystem.HaveBeginRoundTrigger = true

--This being true makes boons combine for rolls.
GameSystem.CombineNegativesForRolls = true

GameSystem.UseBoons = true

GameSystem.AllowBoonsForRoll = function(options)
	if options.type == nil then
		return false
	end

	--can use options.type to query the roll type in here if we want to allow boons for a roll.
	return string.find(options.type, "power_roll") ~= nil
end

GameSystem.ApplyBoons = function(roll, boons)
    if boons == 0 then
        return roll
    end

    local rollInfo = dmhub.ParseRoll(roll)
    if rollInfo == nil then
        return roll
    end

    local baseBoons = (rollInfo.boons or 0) - (rollInfo.banes or 0)
    local newBoons = baseBoons + boons
    rollInfo.boons = nil
    rollInfo.banes = nil

    if newBoons > 0 then
        rollInfo.boons = newBoons
    elseif newBoons < 0 then
        rollInfo.banes = -newBoons
    end

    return dmhub.RollToString(rollInfo)
end

GameSystem.CalculateDeathSavingThrowRoll = function(creature)
    return "1d20"
end

CharacterAttribute.baseValue = 0

--This controls the calculation for the modifier of an attribute. e.g. an attribute of 17 gives a modifier of +3
GameSystem.CalculateAttributeModifier = function(attributeInfo, attributeValue)
    return attributeValue
end

--how initiative is controlled!
GameSystem.BaseInitiativeRoll = "1d20"
GameSystem.LowerInitiativeIsFaster = true

--how the initiative modifier is calculated. Important: If you remove dexterity then also change this!
GameSystem.CalculateInitiativeModifier = function(creature)
	return creature:GetAttribute('dex'):Modifier()
end

--how do we describe an attack?
GameSystem.DescribeAttack = function(ranged, offhand, hit, reach, damage, propertyDescription)
	return string.format("%s%s: %s, %s damage.%s", cond(ranged, "Ranged Attack", "Melee Attack"), offhand, reach, damage, propertyDescription)
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

--the base/default armor class.
GameSystem.BaseArmorClass = 0

--the attribute that modifies armor class.
GameSystem.ArmorClassModifierAttrId = false


--This calculates the bonus damage for an attack with a weapon.
--It can use the bonus from the attribute for the attack bonus (hit bonus)
--by just returning options.attackBonus. Otherwise it can return any
--number.
--
--We can check weapon properties for builtin weapon properties by going e.g. weapon:HasProperty("thrown")
GameSystem.CalculateDamageBonus = function(creature, weapon, options)
    return options.attackBonus
end



--the basic action resources every creature has.
function GameSystem.BaseCreatureResources(creature)
    local result = {
		standardAction = 1,
		movementAction = 1,
		bonusAction = 1,
		reaction = 1,
    }

	if #creature.innateLegendaryActions > 0 and CharacterResource.legendaryAction ~= "none" then
		--creatures with legendary actions get three legendary actions each round.
		result[CharacterResource.legendaryAction] = 3
	end

	return result
end

--the maximum level a spell can be.
GameSystem.maxSpellLevel = 9

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

local g_RegisterAttribute = GameSystem.RegisterAttribute

GameSystem.AttributeByFirstLetter = {}

function GameSystem.RegisterAttribute(info)
    g_RegisterAttribute(info)

    if mod.unloaded then
        return
    end

    GameSystem.AttributeByFirstLetter[string.sub(string.lower(info.id), 1, 1)] = info.id
end

--the attributes available in our system.
GameSystem.RegisterAttribute{
	id = "mgt",
	description = "Might",
	order = 10,
}


GameSystem.RegisterAttribute{
	id = "agl",
	description = "Agility",
	order = 20,
}

GameSystem.RegisterAttribute{
	id = "rea",
	description = "Reason",
	order = 40,
}

GameSystem.RegisterAttribute{
	id = "inu",
	description = "Intuition",
	order = 50,
}

GameSystem.RegisterAttribute{
	id = "prs",
	description = "Presence",
	order = 60,
}

GameSystem.RegisterSavingThrow{
	id = "mgt",
	attrid = "mgt",
	description = "Might",
	order = 10,
}

GameSystem.RegisterSavingThrow{
	id = "agl",
	attrid = "agl",
	description = "Agility",
	order = 20,
}

GameSystem.RegisterSavingThrow{
	id = "rea",
	attrid = "rea",
	description = "Reason",
	order = 40,
}

GameSystem.RegisterSavingThrow{
	id = "inu",
	attrid = "inu",
	description = "Intuition",
	order = 50,
}

GameSystem.RegisterSavingThrow{
	id = "prs",
	attrid = "prs",
	description = "Presence",
	order = 60,
}


--this calculates the saving throw modifier for a saving throw.
--savingThrowInfo: the table given to RegisterSavingThrow. Note that you can add whatever information
--                 you need to RegisterSavingThrow to ensure you can calculate the saving throw modifier.
GameSystem.CalculateSavingThrowModifier = function(creature, savingThrowInfo, proficiencyLevel)
    local attributeModifier = creature:GetAttribute(savingThrowInfo.attrid):Modifier()
    local proficiencyBonus = GameSystem.CalculateProficiencyBonus(creature, proficiencyLevel)

    return attributeModifier + proficiencyBonus
end

GameSystem.RegisterApplyToTargets{
	id = "all_creatures",
	text = "All Creatures in Combat",
}

--when casting a spell, this is our set of 'target lists' who have different outcomes to what has happened in the spell so far.
--it might include lists of creatures who have been hit, made a save, failed a save, been critically hit, etc.
GameSystem.RegisterApplyToTargets{
	--This represents any creatures hit by an attack roll OR a damage effect.
	--It has built-in references, so not recommended to remove.
	--
	--it is also currently the only way to get a list of creatures hit by a contested attack roll.
	id = "hit_targets",
	text = "Targets Hit",
	attack_hit = true,
}

GameSystem.RegisterApplyToTargets{
	--This represents any creature that failed any kind of check.
	--It has built-in references, so not recommended to remove.
	id = "failed_save_targets",
	text = "Targets Who Failed Check",
}

GameSystem.RegisterApplyToTargets{
	--This represents any creature that passed any kind of check.
	--It has built-in references, so not recommended to remove.
	id = "passed_save_targets",
	text = "Targets Who Didn't Fail Check",
	inverse = "failed_save_targets",
}

--a creature that was hit critically.
GameSystem.RegisterApplyToTargets{
	id = "hit_targets_crit",
	text = "Targets Hit Critically",
}

GameSystem.RegisterApplyToTargets{
	id = "failed_save",
	text = "Targets Who Failed Saving Throw",
}

GameSystem.RegisterApplyToTargets{
	id = "passed_save",
	text = "Targets Who Passed Saving Throw",
}

GameSystem.RegisterRollType("attack",
    function(rollRules, armorClass)
        rollRules.lowerIsBetter = false

        --for systems that have the 'degree of success' increase or decrease when getting e.g. a nat20 or nat1, use this
        --to change the degree of success or failure. Don't use fumbleRoll or criticalRoll if you do this.
        rollRules.changeOutcomeOnCriticalRoll = 0
        rollRules.changeOutcomeOnFumbleRoll = 0

        rollRules:AddOutcome{
            outcome = "Miss",
            color = "#ff0000",
			fumbleRoll = true, --this will be chosen automatically on a 'fumble' roll (normally a nat1)
            degree = 1,
            failure = true,
        }

        rollRules:AddOutcome{
            value = armorClass,
            outcome = "Hit",
            color = "#00ff00",
            degree = 1,
            success = true,
        }

        rollRules:AddOutcome{
            value = 999, --this value is too high to get under normal circumstances, only available with a nat20.
            criticalRoll = true, --this will be chosen automatically on a 'critical' roll (normally a nat20)
            outcome = "Critical",
            color = "#00ff00",
            degree = 2,
            success = true,
			applyto = {"hit_targets_crit"},
        }
    end
)

GameSystem.RegisterRollType("attribute",
    function(rollRules, dc)
        rollRules.lowerIsBetter = false

        rollRules:AddOutcome{
            outcome = "Failure",
            color = "#ff0000",
            degree = 1,
            failure = true,
        }

        rollRules:AddOutcome{
            value = dc,
            outcome = "Success",
            color = "#00ff00",
            degree = 1,
            success = true,
        }
    end
)

GameSystem.RegisterRollType("skill",
    function(rollRules, dc)
        rollRules.lowerIsBetter = false

        rollRules:AddOutcome{
            outcome = "Failure",
            color = "#ff0000",
            degree = 1,
            failure = true,
        }

        rollRules:AddOutcome{
            value = dc,
            outcome = "Success",
            color = "#00ff00",
            degree = 1,
            success = true,
        }
    end
)

GameSystem.RegisterRollType("save",
    function(rollRules, dc)
        rollRules.lowerIsBetter = false

        rollRules:AddOutcome{
            outcome = "Failure",
            color = "#ff0000",
            degree = 1,
            failure = true,
			applyto = {"failed_save"},
        }

        rollRules:AddOutcome{
            value = dc,
            outcome = "Success",
            color = "#00ff00",
            degree = 1,
            success = true,
			applyto = {"passed_save"},
        }
    end
)

GameSystem.RegisterRollType("deathsave",
    function(rollRules)
        rollRules.lowerIsBetter = false

        rollRules:AddOutcome{
            outcome = "Critical Fail",
            color = "#ff0000",
			fumbleRoll = true, --this will be chosen automatically on a 'fumble' roll (normally a nat1)
            degree = 2,
            failure = true,
        }

        rollRules:AddOutcome{
            outcome = "Fail",
            color = "#ff0000",
			value = 2,
            degree = 1,
            failure = true,
        }

        rollRules:AddOutcome{
            value = 10,
            outcome = "Success",
            color = "#ff0000",
            degree = 1,
            success = true,
        }

        rollRules:AddOutcome{
            value = 999, --this value is too high to get under normal circumstances, only available with a nat20.
            criticalRoll = true, --this will be chosen automatically on a 'critical' roll (normally a nat20)
            outcome = "Critical Success",
            color = "#ff0000",
            degree = 2,
            success = true,
        }

    end
)

--Example of bonus types we can register.
--GameSystem.RegisterRollBonusType("Circumstance")
--GameSystem.RegisterRollBonusType("Item")
--GameSystem.RegisterRollBonusType("Status")

--which proficiency types are leveled? For 5e we only allow skill proficiencies to level, but for other systems we can add other types of proficiencies.
GameSystem.SetLeveledProficiency("skill") --only 'skill', not 'equipment', 'language', or 'save' for 5e.

--how spell save DC is calculated for a spell. 8 + Spellcasting Ability Modifier + Proficiency Bonus + additional bonuses to Spell Save DC.
GameSystem.CalculateSpellSaveDC = function(creature, spell)
    return creature:CalculateAttribute("spellsavedc", 8 + creature:SpellcastingAbilityModifier(spell) + GameSystem.CalculateProficiencyBonus(creature, GameSystem.Proficient()))
end

--how the spell attack modifier is calculated for a spell.
GameSystem.CalculateSpellAttackModifier = function(creature, spell)
	return creature:CalculateAttribute("spellattackmod", creature:SpellcastingAbilityModifier(spell) + GameSystem.CalculateProficiencyBonus(creature, GameSystem.Proficient()))
end

--how weapon proficiency bonuses are calculated.
GameSystem.CalculateWeaponProficiencyBonus = function(creature, weapon)
    if creature.proficientWithAllWeapons then
        --monsters have this and are just assumed to have basic proficiency with all weapons.
        return GameSystem.CalculateProficiencyBonus(creature, GameSystem.Proficient())
    else
        local proficiencyLevel = creature:ProficiencyLevelWithItem(weapon)
        return GameSystem.CalculateProficiencyBonus(creature, proficiencyLevel)
    end
end

--we give characters and monsters a way to calculate their proficiency bonus.
function character:BaseProficiencyBonus()
    if self:CharacterLevel() >= 6 then
        return 2
    end

    return 1
end

function monster:BaseProficiencyBonus()
    if self:CharacterLevel() >= 6 then
        return 2
    end

    return 1
end

--The way in which proficiency bonus is calculated from a proficiency level.
GameSystem.CalculateProficiencyBonus = function(creature, proficiencyLevel)

	if proficiencyLevel == nil then
        --we got this error condition sometimes, so this diagnostic code is here to send a trace of it to the cloud so DMHub programmers can work out why.
		dmhub.CloudError("nil proficiencyLevel: " .. traceback())
		return 0
	end

    return proficiencyLevel.multiplier
end

--proficiency levels.
GameSystem.RegisterProficiencyLevel{
	id = "none",
	text = "Not Proficient",
	multiplier = 0,
	verboseDescription = tr("You are not proficient in %s."),
}

GameSystem.RegisterProficiencyLevel{
	id = "proficient",
	text = "Proficient",
	multiplier = 1,
	verboseDescription = tr("You are proficient with %s."),
}

--we can register new GoblinScript fields.

GameSystem.RegisterGoblinScriptField{
    name = "Dueling",

    calculate = function(creature)
        return creature:NumberOfWeaponsWielded() == 1 and not creature:WieldingTwoHanded()
    end,

	type = "boolean",
	desc = "True if the creature is wielding only one weapon in one hand.",
	examples = {"Dueling and Unarmored"},
    seealso = {"Weapons Wielded", "Two Handed"},
}

GameSystem.RegisterGoblinScriptField{
    name = "Has Adjacent Enemy Other Than Us",

	type = "function",
	desc = "A function that returns true if there is an enemy adjacent to the target creature other than the creature that we pass in.",
	examples = {"Target.HasAdjacentEnemyOtherThanUs(Self)"},

    calculate = function(targetCreature)
        return function(us)
            local targetToken = dmhub.LookupToken(targetCreature)
            local ourToken = dmhub.LookupToken(us)

            if targetToken == nil or ourToken == nil then
                return false
            end

			local nearbyTokens = targetToken:GetNearbyTokens(1)
			for i,nearby in ipairs(nearbyTokens) do
				if nearby.charid ~= ourToken.charid and (not nearby:IsFriend(targetToken)) then
                    return true
				end
			end

            return false
        end
    end,
}

RegisterGoblinScriptSymbol(creature, {
	name = "Stability",
	type = "number",
	desc = "The stability of this creature",
	examples = {"Self.Stability >= 3"},
	calculate = function(c)
		return c:Stability()
	end,
})

--We can register attributes that can be modified by Modify Attribute like this.
GameSystem.RegisterModifiableAttribute{
    id = "ignoreoffhandpenalty",
    text = "Ignore Offhand Damage Penalty",
    attributeType = "number",
    category = "Combat",
}

--This is used to tell if we ignore off hand weapon penalties.
function GameSystem.IgnoreOffhandWeaponPenalty(creature, weapon)
	return creature:CalculateAttribute('ignoreoffhandpenalty', 0) > 0
end

GameSystem.ClearWeaponProperties()

--builtin weapon properties. We allow registration of more weapon
--properties in the compendium, but these are any that are fundamental to the
--game system and might be referenced in code directly by their ID.
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Ammo'), attr = 'ammo' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Range'), attr = 'range' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Thrown'), attr = 'thrown' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Loading'), attr = 'loading' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Light'), attr = 'light' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Heavy'), attr = 'heavy' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Finesse'), attr = 'finesse' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Reach'), attr = 'reach' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Versatile'), attr = 'versatile' }


-- HITPOINTS

--This calculates the rules text describing a class's hitpoint progression in the character builder.
GameSystem.GenerateClassHitpointsRulesText = function(class)
	return ""
end

--whether rolling for hitpoints is something characters can do when they level up.
GameSystem.allowRollForHitpoints = true

--Hitpoints can be negative.
GameSystem.allowNegativeHitpoints = true

--the number of hitpoints gained each level when using fixed hitpoints
GameSystem.FixedHitpointsForLevel = function(class, firstLevel)
	return 0
end

--additional hitpoints when leveling up aside from what the class provides.
GameSystem.BonusHitpointsForLevel = function(creature)
	return 0
end

--how we briefly describe what the bonus hitpoints per level is calculated from.
GameSystem.bonusHitpointsForLevelRulesText = tr("")

--does this game system use hit dice?
GameSystem.haveHitDice = false

--does this game system have temporary hitpoints?
GameSystem.haveTemporaryHitpoints = true

--do races list features for each and every level?
GameSystem.racesHaveLeveling = false

GameSystem.numLevels = 10

--if true, then ranged attacks will have a 'near' and 'far' range, the far range being made at disadvantage.
GameSystem.attacksAtLongRangeHaveDisadvantage = false

--if this is true, then attack behaviors can have weapon properties.
GameSystem.attacksCanHaveWeaponProperties = false


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

GameSystem.CharacterBuilderShowsHitpoints = false

GameSystem.RegisterAbilityKeyword("Animal")
GameSystem.RegisterAbilityKeyword("Area")
GameSystem.RegisterAbilityKeyword("Strike")
GameSystem.RegisterAbilityKeyword("Focus")
GameSystem.RegisterAbilityKeyword("Kit")
GameSystem.RegisterAbilityKeyword("Magic")
GameSystem.RegisterAbilityKeyword("Melee")
GameSystem.RegisterAbilityKeyword("Psionic")
GameSystem.RegisterAbilityKeyword("Weapon")
GameSystem.RegisterAbilityKeyword("Ranged")
GameSystem.RegisterAbilityKeyword("Telepathy")
GameSystem.RegisterAbilityKeyword("Air")
GameSystem.RegisterAbilityKeyword("Earth")
GameSystem.RegisterAbilityKeyword("Fire")
GameSystem.RegisterAbilityKeyword("Green")
GameSystem.RegisterAbilityKeyword("Rot")
GameSystem.RegisterAbilityKeyword("Void")
GameSystem.RegisterAbilityKeyword("Water")
GameSystem.RegisterAbilityKeyword("Routine")
GameSystem.RegisterAbilityKeyword("Performance")
GameSystem.RegisterAbilityKeyword("Beastheart")
GameSystem.RegisterAbilityKeyword("Companion")
GameSystem.RegisterAbilityKeyword("Potion")
GameSystem.RegisterAbilityKeyword("Neck")
GameSystem.RegisterAbilityKeyword("Charge")

GameSystem.RegisterAbilityKeyword("Light Armor")
GameSystem.RegisterAbilityKeyword("Medium Armor")
GameSystem.RegisterAbilityKeyword("Heavy Armor")

GameSystem.RegisterAbilityCategorization{category = "Heroic Ability", grouping = "Heroic Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Villain Action", grouping = "Villain Actions"}
GameSystem.RegisterAbilityCategorization{category = "Malice", grouping = "Malice Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Signature Ability", grouping = "Signature Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Ability", grouping = "Common Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Trigger", grouping = "Triggers"}
GameSystem.RegisterAbilityCategorization{category = "Skill", grouping = "Common Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Basic Attack", grouping = "Common Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Move", grouping = "Move"}
GameSystem.RegisterAbilityCategorization{category = "Hidden", grouping = "Common Abilities"}

GameSystem.ActionBarGroupings = {
    ["Heroic Abilities"] = 1,
    ["Malice Abilities"] = 2,
    ["Signature Abilities"] = 3,
    ["Common Abilities"] = 4,
    ["Triggers"] = 5,
}

function GameSystem.GetAbilityCategoryInfo(category)
    return GameSystem.abilityCategories[category] or {
        category = category,
        order = 1000,
    }
end

--set the default categorization.
ActivatedAbility.categorization = "Skill"



--the only type of resistance we need is damage reduction.
ResistanceEntry.types = {"Damage Reduction"}

--override available refresh options.
CharacterResource.RegisterRefreshOptions{
	{
		id = 'none',
		text = 'No usage limit',
		refreshDescription = 'always',
	},
	{
		id = 'turn',
		text = 'Per Turn',
		refreshDescription = 'each turn',
	},
	{
		id = 'round',
		text = 'Per Round',
		refreshDescription = 'each round',
	},
	{
		id = 'encounter',
		text = 'Per Encounter',
		refreshDescription = 'each encounter',
	},
	{
		id = 'long',
		text = 'Per Rest',
		refreshDescription = 'on rest',
	},
	{
		id = 'never',
		text = 'Manual Refresh',
		refreshDescription = 'manually',
	},
	{
		id = 'unbounded',
		text = 'Unbounded',
		refreshDescription = 'unbounded',
	},
	{
		id = 'global',
		text = 'Global',
		refreshDescription = 'global',
	},
}

--always just use squares for measurements.
MeasurementSystem.systems = {
	MeasurementSystem.new{
        value = "Tiles",
        text = "Squares",
		unitName = "Squares",
        unitSingular = "Square",
        abbreviation = "",
        tileSize = 1,
	},
}

setting{
    id = "measurementsystem",
    description = "Measurement Units",
    storage = "preference",
    editor = "dropdown",
    default = "Tiles",
    enum = MeasurementSystem.systems,
}

dmhub.unitsPerSquare = 1


--default damage type is 'untyped' damage.
ActivatedAbilityBehavior.damageType = "untyped"

GameSystem.RegisterConditionRule{
	id = "unconscious",
	conditions = {"Unbalanced"},

	rule = function(targetCreature, modifiers)
		return targetCreature:MaxHitpoints(modifiers) <= targetCreature.damage_taken
	end,
}

local g_abilitySymbols = {
    {
        name = "Used Ability",
        type = "ability",
        desc = "The ability used",
    },
    {
        name = "Cast",
        type = "cast",
        desc = "Casting information for the ability",
    }
}

TriggeredAbility.RegisterTrigger{
    id = "inflictcondition",
    text = "Condition Applied",
    symbols = {
        condition = {
            name = "Condition",
            type = "string",
            desc = "The name of the condition applied.",
        },
        attacker = {
            name = "Attacker",
            type = "creature",
            desc = "The attacking creature. Only valid if Has Attacker is true.",
        },
        hasattacker = {
            name = "Has Attacker",
            type = "boolean",
            desc = "True if a known creature inflicted the condition.",
        },
    }
}

TriggeredAbility.RegisterTrigger{
    id = "movethrough",
    text = "Move Through Creature",
    symbols = {
        target = {
            name = "Target",
            type = "creature",
            desc = "The creature being moved through.",
        },
    }
}

TriggeredAbility.RegisterTrigger{
    id = "teleport",
    text = "Teleport",
    symbols = {}
}

TriggeredAbility.RegisterTrigger{
    id = "leaveadjacent",
    text = "Creature Moved Away From",
    symbols = {
        movingcreature = {
            name = "Moving Creature",
            type = "creature",
            desc = "The creature moving away.",
        },
    },
}

TriggeredAbility.RegisterTrigger{
    id = "gaintempstamina",
    text = "Gain Temporary Stamina",
    symbols = {},
}

TriggeredAbility.RegisterTrigger{
    id = "castsignature",
    text = "Use Signature Attack or Area",
    symbols = g_abilitySymbols,
}

TriggeredAbility.RegisterTrigger{
    id = "useresource",
    text = "Use Resource",
    symbols = {
        resource = {
            name = "Resource",
            type = "string",
            desc = "The resource used.",
        },
        quantity = {
            name = "Quantity",
            type = "number",
            desc = "The number of resources used.",
        }
    }
}

TriggeredAbility.RegisterTrigger{
    id = "gainresource",
    text = "Gain Resource",
    symbols = {
        resource = {
            name = "Resource",
            type = "string",
            desc = "The resource used.",
        },
        quantity = {
            name = "Quantity",
            type = "number",
            desc = "The number of resources used.",
        }
    }
}

TriggeredAbility.RegisterTrigger{
    id = "useability",
    text = "Use an Ability",
    symbols = g_abilitySymbols,
}

GameSystem.OnEndCastActivatedAbility = function(casterToken, ability, options)
    if not ability:CountsAsRegularAbilityCast() then
        return
    end

    if options.abort then
        return
    end

    ability:FireUseAbility(casterToken, options)

	if ability.categorization == "Signature Ability" and (ability:HasKeyword("Area") or ability:HasKeyword("Strike")) then
		casterToken.properties:DispatchEvent("castsignature", {ability = ability, cast = options.symbols.cast})
	end
end

local friendlyFire = setting{
    id = "friendlyfire",
    description = "Friendly Fire",
    storage = "game",
	section = "game",
	editor = "check",
    dmonly = true,
    default = false,
}

function GameSystem.AllowTargeting(casterToken, targetToken, ability)
	if friendlyFire:Get() == false and ability:HasKeyword("Strike") and ability:HasKeyword("Area") and casterToken:IsFriend(targetToken) then
		return false
	end

	return true
end

CharSheet.DeregisterTab("Spells")

GameSystem.RegisterCreatureSizes{
	{
		name = "1T",
		tiles = 1,
		radius = 0.2,
	},
	{
		name = "1S",
		tiles = 1,
		radius = 0.32,
	},
	{
		name = "1M",
		tiles = 1,
		radius = 0.4,
		defaultSize = true,
	},
	{
		name = "1L",
		tiles = 1,
		radius = 0.5,
	},
	{
		name = "2",
		tiles = 2,
		radius = 0.85,
	},
	{
		name = "3",
		tiles = 3,
		radius = 1.35,
	},
	{
		name = "4",
		tiles = 4,
		radius = 1.7,
	},
	{
		name = "5",
		tiles = 5,
		radius = 2.2,
	},
    {
		name = "6",
		tiles = 6,
		radius = 2.7,
	},
}

Race.size = "1M"

--override the default type for damage resistance.
ResistanceEntry.apply = 'Damage Reduction'

GameSystem.TierNames = {
	"11 or lower",
	"12-16",
	"17+",
}

GameSystem.abilitiesHaveAttribute = false
GameSystem.abilitiesHaveDuration = false

GameSystem.minionsPerSquad = 4
GameSystem.minionsPerSquadText = "four"

GameSystem.GameMasterShortName = "Director"
GameSystem.GameMasterLongName = "Director"

CharacterModifier.DeregisterType("Armor Class Calculation")
CharacterModifier.DeregisterType("Attack Attribute")
CharacterModifier.DeregisterType("Custom Spellcasting")
CharacterModifier.DeregisterType("Damage Multiplier After Save")
CharacterModifier.DeregisterType("Grant Spell List")
CharacterModifier.DeregisterType("Grant Spells")
CharacterModifier.DeregisterType("Innate Spellcasting")
CharacterModifier.DeregisterType("Modify Damage")
CharacterModifier.DeregisterType("Multiple Attacks")
CharacterModifier.DeregisterType("Rolls Attacking Us")
CharacterModifier.DeregisterType("Spellcasting")

ActivatedAbility.SuppressType("Attack")
ActivatedAbility.SuppressType("Cast Spell")
ActivatedAbility.SuppressType("Contested Attack")
ActivatedAbility.SuppressType("Forced Movement")
ActivatedAbility.SuppressType("Saving Throw")

function TriggeredAbility.DeregisterTrigger(triggerid)
	for i,entry in ipairs(TriggeredAbility.triggers) do
		if entry.id == triggerid then
            table.remove(TriggeredAbility.triggers, i)
			break
		end
	end
end

TriggeredAbility.DeregisterTrigger("hit")

TriggeredAbility.RegisterTrigger{
    id = "targetwithability",
    text = "Target With Ability",
    symbols = {
        ability = {
            name = "Used Ability",
            type = "ability",
            desc = "The ability used.",
        },
        target = {
            name = "Target",
            type = "creature",
            desc = "The target creature.",
        }
    },
}



TriggeredAbility.RegisterTrigger{
    id = "losehitpoints",
    text = "Take Damage",
    symbols = {
        damage = {
            name = "Damage",
            type = "number",
            desc = "The amount of damage taken when triggering this event.",
        },
        rawdamage = {
            name = "Raw Damage",
            type = "number", 
            desc = "The amount of damage taken before any immunities or damage reduction.",
        },
        damagetype = {
            name = "Damage Type",
            type = "text",
            desc = "The type of damage taken when triggering this event.",
        },
        damageimmunity = {
            name = "Damage Immunity",
            type = "boolean",
            desc = "True if the damage was reduced or increased due to a damage immunity or weakness.",
        },
        keywords = {
            name = "Keywords",
            type = "set",
            desc = "The keywords used to apply the damage.",
        },
        surges = {
            name = "Surges",
            type = "number",
            desc = "The number of surges used for this damage.",
        },
        edges = {
            name = "Edges",
            type = "number",
            desc = "The number of edges used for this damage.",
        },
        banes = {
            name = "Banes",
            type = "number",
            desc = "The number of banes used for this damage.",
        },
        attacker = {
            name = "Attacker",
            type = "creature",
            desc = "The attacking creature. Only valid if Has Attacker is true.",
        },
        hasattacker = {
            name = "HasAttacker",
            type = "boolean",
            desc = "True if the damage has an attacker.",
        },
        hasability = {
            name = "HasAbility",
            type = "boolean",
            desc = "True if the damage has an ability.",
        },
        ability = {
            name = "Ability",
            type = "ability",
            desc = "The ability used.",
        },
    },

    examples = {
        {
            script = "damage > 8 and (damage type is slashing or damage type is piercing)",
            text = "The triggered ability only activates if more than 8 damage was done and the damage was slashing or piercing damage."
        }
    },
}

TriggeredAbility.RegisterTrigger{
    id = "dealdamage",
    text = "Damage an Enemy",
    symbols = {
        {
            name = "Damage",
            type = "number",
            desc = "The amount of damage dealt.",
        },
        {
            name = "Damage Type",
            type = "text",
            desc = "The type of damage dealt.",
        },
        {
            name = "Keywords",
            type = "set",
            desc = "The keywords used to apply the damage.",
        },
        {
            name = "Target",
            type = "creature",
            desc = "The target creature.",
        },
        {
            name = "Surges",
            type = "number",
            desc = "The number of surges applied to the damage.",
        },
        {
            name = "Edges",
            type = "number",
            desc = "The number of edges used for this damage.",
        },
        {
            name = "Banes",
            type = "number",
            desc = "The number of banes used for this damage.",
        },
        {
            name = "HasAbility",
            type = "boolean",
            desc = "True if the damage has an ability associated with it.",
        },
        {
            name = "Ability",
            type = "ability",
            desc = "The ability used to deal the damage. Only valid if HasAbility is true.",
        }
    }
}

TriggeredAbility.RegisterTrigger{
    id = "rollpower",
    text = "Roll Power",
    symbols = {
        {
            name = "Natural Roll",
            type = "number",
            desc = "The dice roll without any modifiers.",
        },
        {
            name = "Surges",
            type = "number",
            desc = "The number of surges used (across all targets).",
        },
        {
            name = "Tier One",
            type = "boolean",
            desc = "True if there was a tier one result (on at least one target).",
        },
        {
            name = "Tier Two",
            type = "boolean",
            desc = "True if there was a tier two result (on at least one target).",
        },
        {
            name = "Tier Three",
            type = "boolean",
            desc = "True if there was a tier three result (on at least one target).",
        },
        {
            name = "Ability",
            type = "ability",
            desc = "The ability used for the Power Roll.",
        },
    }
}

--redefine hitpoints as stamina.
CustomAttribute.RegisterAttribute{ id = "hitpoints", text = "Stamina", attributeType = "number", category = "Basic Attributes"}
CustomAttribute.DeregisterAttribute("armorClass")
CustomAttribute.DeregisterAttribute("initiativeBonus")
CustomAttribute.DeregisterAttribute("proficiencyBonus")
CustomAttribute.DeregisterAttribute("spellLevel")
CustomAttribute.DeregisterAttribute("spellcastingClasses")
CustomAttribute.DeregisterAttribute("spellsaveddc")
CustomAttribute.DeregisterAttribute("spellattackmod")

GameSystem.encumbrance = false
local mod = dmhub.GetModLoading()


--this resets the game rules, allowing us to start from scratch and define our system.
GameSystem.ClearRules()

--what this game system calls things.
GameSystem.HitpointsName = "Stamina"
GameSystem.AttributeName = "Characteristic"
GameSystem.AttributeNamePlural = "Characteristics"
GameSystem.SkillName = "Skill"
GameSystem.SkillNamePlural = "Skills"
GameSystem.SavingThrowName = "Resistance"
GameSystem.SavingThrowRollName = "Reactive Test"
GameSystem.SavingThrowNamePlural = "Resistances"

GameSystem.BackgroundName = "Career"
GameSystem.BackgroundNamePlural = "Careers"
GameSystem.RaceName = "Ancestry"
GameSystem.RaceNamePlural = "Ancestries"
GameSystem.RacesHaveHeights = false
GameSystem.CRName = "LVL"
GameSystem.ChallengeName = "Level"
GameSystem.ChallengeRatingName = "Level"

--what the basic rolls look like in our system.
GameSystem.BaseAttackRoll = "2d10"
GameSystem.BaseSkillRoll = "2d10"
GameSystem.BaseSavingThrowRoll = "2d10"
GameSystem.FlatRoll = "2d10"

--do critical hits modify damage in this game system?
GameSystem.CriticalHitsModifyDamage = false

--start of round is an important trigger.
GameSystem.HaveBeginRoundTrigger = true

--This being true makes boons combine for rolls.
GameSystem.CombineNegativesForRolls = true

GameSystem.UseBoons = true

GameSystem.AllowBoonsForRoll = function(options)
	if options.type == nil then
		return false
	end

	--can use options.type to query the roll type in here if we want to allow boons for a roll.
	return string.find(options.type, "power_roll") ~= nil
end

GameSystem.ApplyBoons = function(roll, boons)
    if boons == 0 then
        return roll
    end

    local rollInfo = dmhub.ParseRoll(roll)
    if rollInfo == nil then
        return roll
    end

    local baseBoons = (rollInfo.boons or 0) - (rollInfo.banes or 0)
    local newBoons = baseBoons + boons
    rollInfo.boons = nil
    rollInfo.banes = nil

    if newBoons > 0 then
        rollInfo.boons = newBoons
    elseif newBoons < 0 then
        rollInfo.banes = -newBoons
    end

    return dmhub.RollToString(rollInfo)
end

GameSystem.CalculateDeathSavingThrowRoll = function(creature)
    return "1d20"
end

CharacterAttribute.baseValue = 0

--This controls the calculation for the modifier of an attribute. e.g. an attribute of 17 gives a modifier of +3
GameSystem.CalculateAttributeModifier = function(attributeInfo, attributeValue)
    return attributeValue
end

--how initiative is controlled!
GameSystem.BaseInitiativeRoll = "1d20"
GameSystem.LowerInitiativeIsFaster = true

--how the initiative modifier is calculated. Important: If you remove dexterity then also change this!
GameSystem.CalculateInitiativeModifier = function(creature)
	return creature:GetAttribute('dex'):Modifier()
end

--how do we describe an attack?
GameSystem.DescribeAttack = function(ranged, offhand, hit, reach, damage, propertyDescription)
	return string.format("%s%s: %s, %s damage.%s", cond(ranged, "Ranged Attack", "Melee Attack"), offhand, reach, damage, propertyDescription)
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

--the base/default armor class.
GameSystem.BaseArmorClass = 0

--the attribute that modifies armor class.
GameSystem.ArmorClassModifierAttrId = false


--This calculates the bonus damage for an attack with a weapon.
--It can use the bonus from the attribute for the attack bonus (hit bonus)
--by just returning options.attackBonus. Otherwise it can return any
--number.
--
--We can check weapon properties for builtin weapon properties by going e.g. weapon:HasProperty("thrown")
GameSystem.CalculateDamageBonus = function(creature, weapon, options)
    return options.attackBonus
end



--the basic action resources every creature has.
function GameSystem.BaseCreatureResources(creature)
    local result = {
		standardAction = 1,
		movementAction = 1,
		bonusAction = 1,
		reaction = 1,
    }

	if #creature.innateLegendaryActions > 0 and CharacterResource.legendaryAction ~= "none" then
		--creatures with legendary actions get three legendary actions each round.
		result[CharacterResource.legendaryAction] = 3
	end

	return result
end

--the maximum level a spell can be.
GameSystem.maxSpellLevel = 9

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

local g_RegisterAttribute = GameSystem.RegisterAttribute

GameSystem.AttributeByFirstLetter = {}

function GameSystem.RegisterAttribute(info)
    g_RegisterAttribute(info)

    if mod.unloaded then
        return
    end

    GameSystem.AttributeByFirstLetter[string.sub(string.lower(info.id), 1, 1)] = info.id
end

--the attributes available in our system.
GameSystem.RegisterAttribute{
	id = "mgt",
	description = "Might",
	order = 10,
}


GameSystem.RegisterAttribute{
	id = "agl",
	description = "Agility",
	order = 20,
}

GameSystem.RegisterAttribute{
	id = "rea",
	description = "Reason",
	order = 40,
}

GameSystem.RegisterAttribute{
	id = "inu",
	description = "Intuition",
	order = 50,
}

GameSystem.RegisterAttribute{
	id = "prs",
	description = "Presence",
	order = 60,
}

GameSystem.RegisterSavingThrow{
	id = "mgt",
	attrid = "mgt",
	description = "Might",
	order = 10,
}

GameSystem.RegisterSavingThrow{
	id = "agl",
	attrid = "agl",
	description = "Agility",
	order = 20,
}

GameSystem.RegisterSavingThrow{
	id = "rea",
	attrid = "rea",
	description = "Reason",
	order = 40,
}

GameSystem.RegisterSavingThrow{
	id = "inu",
	attrid = "inu",
	description = "Intuition",
	order = 50,
}

GameSystem.RegisterSavingThrow{
	id = "prs",
	attrid = "prs",
	description = "Presence",
	order = 60,
}


--this calculates the saving throw modifier for a saving throw.
--savingThrowInfo: the table given to RegisterSavingThrow. Note that you can add whatever information
--                 you need to RegisterSavingThrow to ensure you can calculate the saving throw modifier.
GameSystem.CalculateSavingThrowModifier = function(creature, savingThrowInfo, proficiencyLevel)
    local attributeModifier = creature:GetAttribute(savingThrowInfo.attrid):Modifier()
    local proficiencyBonus = GameSystem.CalculateProficiencyBonus(creature, proficiencyLevel)

    return attributeModifier + proficiencyBonus
end

GameSystem.RegisterApplyToTargets{
	id = "all_creatures",
	text = "All Creatures in Combat",
}

--when casting a spell, this is our set of 'target lists' who have different outcomes to what has happened in the spell so far.
--it might include lists of creatures who have been hit, made a save, failed a save, been critically hit, etc.
GameSystem.RegisterApplyToTargets{
	--This represents any creatures hit by an attack roll OR a damage effect.
	--It has built-in references, so not recommended to remove.
	--
	--it is also currently the only way to get a list of creatures hit by a contested attack roll.
	id = "hit_targets",
	text = "Targets Hit",
	attack_hit = true,
}

GameSystem.RegisterApplyToTargets{
	--This represents any creature that failed any kind of check.
	--It has built-in references, so not recommended to remove.
	id = "failed_save_targets",
	text = "Targets Who Failed Check",
}

GameSystem.RegisterApplyToTargets{
	--This represents any creature that passed any kind of check.
	--It has built-in references, so not recommended to remove.
	id = "passed_save_targets",
	text = "Targets Who Didn't Fail Check",
	inverse = "failed_save_targets",
}

--a creature that was hit critically.
GameSystem.RegisterApplyToTargets{
	id = "hit_targets_crit",
	text = "Targets Hit Critically",
}

GameSystem.RegisterApplyToTargets{
	id = "failed_save",
	text = "Targets Who Failed Saving Throw",
}

GameSystem.RegisterApplyToTargets{
	id = "passed_save",
	text = "Targets Who Passed Saving Throw",
}

GameSystem.RegisterRollType("attack",
    function(rollRules, armorClass)
        rollRules.lowerIsBetter = false

        --for systems that have the 'degree of success' increase or decrease when getting e.g. a nat20 or nat1, use this
        --to change the degree of success or failure. Don't use fumbleRoll or criticalRoll if you do this.
        rollRules.changeOutcomeOnCriticalRoll = 0
        rollRules.changeOutcomeOnFumbleRoll = 0

        rollRules:AddOutcome{
            outcome = "Miss",
            color = "#ff0000",
			fumbleRoll = true, --this will be chosen automatically on a 'fumble' roll (normally a nat1)
            degree = 1,
            failure = true,
        }

        rollRules:AddOutcome{
            value = armorClass,
            outcome = "Hit",
            color = "#00ff00",
            degree = 1,
            success = true,
        }

        rollRules:AddOutcome{
            value = 999, --this value is too high to get under normal circumstances, only available with a nat20.
            criticalRoll = true, --this will be chosen automatically on a 'critical' roll (normally a nat20)
            outcome = "Critical",
            color = "#00ff00",
            degree = 2,
            success = true,
			applyto = {"hit_targets_crit"},
        }
    end
)

GameSystem.RegisterRollType("attribute",
    function(rollRules, dc)
        rollRules.lowerIsBetter = false

        rollRules:AddOutcome{
            outcome = "Failure",
            color = "#ff0000",
            degree = 1,
            failure = true,
        }

        rollRules:AddOutcome{
            value = dc,
            outcome = "Success",
            color = "#00ff00",
            degree = 1,
            success = true,
        }
    end
)

GameSystem.RegisterRollType("skill",
    function(rollRules, dc)
        rollRules.lowerIsBetter = false

        rollRules:AddOutcome{
            outcome = "Failure",
            color = "#ff0000",
            degree = 1,
            failure = true,
        }

        rollRules:AddOutcome{
            value = dc,
            outcome = "Success",
            color = "#00ff00",
            degree = 1,
            success = true,
        }
    end
)

GameSystem.RegisterRollType("save",
    function(rollRules, dc)
        rollRules.lowerIsBetter = false

        rollRules:AddOutcome{
            outcome = "Failure",
            color = "#ff0000",
            degree = 1,
            failure = true,
			applyto = {"failed_save"},
        }

        rollRules:AddOutcome{
            value = dc,
            outcome = "Success",
            color = "#00ff00",
            degree = 1,
            success = true,
			applyto = {"passed_save"},
        }
    end
)

GameSystem.RegisterRollType("deathsave",
    function(rollRules)
        rollRules.lowerIsBetter = false

        rollRules:AddOutcome{
            outcome = "Critical Fail",
            color = "#ff0000",
			fumbleRoll = true, --this will be chosen automatically on a 'fumble' roll (normally a nat1)
            degree = 2,
            failure = true,
        }

        rollRules:AddOutcome{
            outcome = "Fail",
            color = "#ff0000",
			value = 2,
            degree = 1,
            failure = true,
        }

        rollRules:AddOutcome{
            value = 10,
            outcome = "Success",
            color = "#ff0000",
            degree = 1,
            success = true,
        }

        rollRules:AddOutcome{
            value = 999, --this value is too high to get under normal circumstances, only available with a nat20.
            criticalRoll = true, --this will be chosen automatically on a 'critical' roll (normally a nat20)
            outcome = "Critical Success",
            color = "#ff0000",
            degree = 2,
            success = true,
        }

    end
)

--Example of bonus types we can register.
--GameSystem.RegisterRollBonusType("Circumstance")
--GameSystem.RegisterRollBonusType("Item")
--GameSystem.RegisterRollBonusType("Status")

--which proficiency types are leveled? For 5e we only allow skill proficiencies to level, but for other systems we can add other types of proficiencies.
GameSystem.SetLeveledProficiency("skill") --only 'skill', not 'equipment', 'language', or 'save' for 5e.

--how spell save DC is calculated for a spell. 8 + Spellcasting Ability Modifier + Proficiency Bonus + additional bonuses to Spell Save DC.
GameSystem.CalculateSpellSaveDC = function(creature, spell)
    return creature:CalculateAttribute("spellsavedc", 8 + creature:SpellcastingAbilityModifier(spell) + GameSystem.CalculateProficiencyBonus(creature, GameSystem.Proficient()))
end

--how the spell attack modifier is calculated for a spell.
GameSystem.CalculateSpellAttackModifier = function(creature, spell)
	return creature:CalculateAttribute("spellattackmod", creature:SpellcastingAbilityModifier(spell) + GameSystem.CalculateProficiencyBonus(creature, GameSystem.Proficient()))
end

--how weapon proficiency bonuses are calculated.
GameSystem.CalculateWeaponProficiencyBonus = function(creature, weapon)
    if creature.proficientWithAllWeapons then
        --monsters have this and are just assumed to have basic proficiency with all weapons.
        return GameSystem.CalculateProficiencyBonus(creature, GameSystem.Proficient())
    else
        local proficiencyLevel = creature:ProficiencyLevelWithItem(weapon)
        return GameSystem.CalculateProficiencyBonus(creature, proficiencyLevel)
    end
end

--we give characters and monsters a way to calculate their proficiency bonus.
function character:BaseProficiencyBonus()
    if self:CharacterLevel() >= 6 then
        return 2
    end

    return 1
end

function monster:BaseProficiencyBonus()
    if self:CharacterLevel() >= 6 then
        return 2
    end

    return 1
end

--The way in which proficiency bonus is calculated from a proficiency level.
GameSystem.CalculateProficiencyBonus = function(creature, proficiencyLevel)

	if proficiencyLevel == nil then
        --we got this error condition sometimes, so this diagnostic code is here to send a trace of it to the cloud so DMHub programmers can work out why.
		dmhub.CloudError("nil proficiencyLevel: " .. traceback())
		return 0
	end

    return proficiencyLevel.multiplier
end

--proficiency levels.
GameSystem.RegisterProficiencyLevel{
	id = "none",
	text = "Not Proficient",
	multiplier = 0,
	verboseDescription = tr("You are not proficient in %s."),
}

GameSystem.RegisterProficiencyLevel{
	id = "proficient",
	text = "Proficient",
	multiplier = 1,
	verboseDescription = tr("You are proficient with %s."),
}

--we can register new GoblinScript fields.

GameSystem.RegisterGoblinScriptField{
    name = "Dueling",

    calculate = function(creature)
        return creature:NumberOfWeaponsWielded() == 1 and not creature:WieldingTwoHanded()
    end,

	type = "boolean",
	desc = "True if the creature is wielding only one weapon in one hand.",
	examples = {"Dueling and Unarmored"},
    seealso = {"Weapons Wielded", "Two Handed"},
}

GameSystem.RegisterGoblinScriptField{
    name = "Has Adjacent Enemy Other Than Us",

	type = "function",
	desc = "A function that returns true if there is an enemy adjacent to the target creature other than the creature that we pass in.",
	examples = {"Target.HasAdjacentEnemyOtherThanUs(Self)"},

    calculate = function(targetCreature)
        return function(us)
            local targetToken = dmhub.LookupToken(targetCreature)
            local ourToken = dmhub.LookupToken(us)

            if targetToken == nil or ourToken == nil then
                return false
            end

			local nearbyTokens = targetToken:GetNearbyTokens(1)
			for i,nearby in ipairs(nearbyTokens) do
				if nearby.charid ~= ourToken.charid and (not nearby:IsFriend(targetToken)) then
                    return true
				end
			end

            return false
        end
    end,
}

RegisterGoblinScriptSymbol(creature, {
	name = "Stability",
	type = "number",
	desc = "The stability of this creature",
	examples = {"Self.Stability >= 3"},
	calculate = function(c)
		return c:Stability()
	end,
})

--We can register attributes that can be modified by Modify Attribute like this.
GameSystem.RegisterModifiableAttribute{
    id = "ignoreoffhandpenalty",
    text = "Ignore Offhand Damage Penalty",
    attributeType = "number",
    category = "Combat",
}

--This is used to tell if we ignore off hand weapon penalties.
function GameSystem.IgnoreOffhandWeaponPenalty(creature, weapon)
	return creature:CalculateAttribute('ignoreoffhandpenalty', 0) > 0
end

GameSystem.ClearWeaponProperties()

--builtin weapon properties. We allow registration of more weapon
--properties in the compendium, but these are any that are fundamental to the
--game system and might be referenced in code directly by their ID.
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Ammo'), attr = 'ammo' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Range'), attr = 'range' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Thrown'), attr = 'thrown' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Loading'), attr = 'loading' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Light'), attr = 'light' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Heavy'), attr = 'heavy' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Finesse'), attr = 'finesse' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Reach'), attr = 'reach' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Versatile'), attr = 'versatile' }


-- HITPOINTS

--This calculates the rules text describing a class's hitpoint progression in the character builder.
GameSystem.GenerateClassHitpointsRulesText = function(class)
	return ""
end

--whether rolling for hitpoints is something characters can do when they level up.
GameSystem.allowRollForHitpoints = true

--Hitpoints can be negative.
GameSystem.allowNegativeHitpoints = true

--the number of hitpoints gained each level when using fixed hitpoints
GameSystem.FixedHitpointsForLevel = function(class, firstLevel)
	return 0
end

--additional hitpoints when leveling up aside from what the class provides.
GameSystem.BonusHitpointsForLevel = function(creature)
	return 0
end

--how we briefly describe what the bonus hitpoints per level is calculated from.
GameSystem.bonusHitpointsForLevelRulesText = tr("")

--does this game system use hit dice?
GameSystem.haveHitDice = false

--does this game system have temporary hitpoints?
GameSystem.haveTemporaryHitpoints = true

--do races list features for each and every level?
GameSystem.racesHaveLeveling = false

GameSystem.numLevels = 10

--if true, then ranged attacks will have a 'near' and 'far' range, the far range being made at disadvantage.
GameSystem.attacksAtLongRangeHaveDisadvantage = false

--if this is true, then attack behaviors can have weapon properties.
GameSystem.attacksCanHaveWeaponProperties = false


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

GameSystem.CharacterBuilderShowsHitpoints = false

GameSystem.RegisterAbilityKeyword("Animal")
GameSystem.RegisterAbilityKeyword("Area")
GameSystem.RegisterAbilityKeyword("Strike")
GameSystem.RegisterAbilityKeyword("Focus")
GameSystem.RegisterAbilityKeyword("Kit")
GameSystem.RegisterAbilityKeyword("Magic")
GameSystem.RegisterAbilityKeyword("Melee")
GameSystem.RegisterAbilityKeyword("Psionic")
GameSystem.RegisterAbilityKeyword("Weapon")
GameSystem.RegisterAbilityKeyword("Ranged")
GameSystem.RegisterAbilityKeyword("Telepathy")
GameSystem.RegisterAbilityKeyword("Air")
GameSystem.RegisterAbilityKeyword("Earth")
GameSystem.RegisterAbilityKeyword("Fire")
GameSystem.RegisterAbilityKeyword("Green")
GameSystem.RegisterAbilityKeyword("Rot")
GameSystem.RegisterAbilityKeyword("Void")
GameSystem.RegisterAbilityKeyword("Water")
GameSystem.RegisterAbilityKeyword("Routine")
GameSystem.RegisterAbilityKeyword("Performance")
GameSystem.RegisterAbilityKeyword("Beastheart")
GameSystem.RegisterAbilityKeyword("Companion")
GameSystem.RegisterAbilityKeyword("Charge")
GameSystem.RegisterAbilityKeyword("Telekinesis")
GameSystem.RegisterAbilityKeyword("Chronopathy")

GameSystem.RegisterItemKeyword("Potion")
GameSystem.RegisterItemKeyword("Neck")

GameSystem.RegisterItemKeyword("Light Armor")
GameSystem.RegisterItemKeyword("Medium Armor")
GameSystem.RegisterItemKeyword("Heavy Armor")
GameSystem.RegisterItemKeyword("Oil")
GameSystem.RegisterItemKeyword("Scroll")
GameSystem.RegisterItemKeyword("Arms")
GameSystem.RegisterItemKeyword("Hands")
GameSystem.RegisterItemKeyword("Head")
GameSystem.RegisterItemKeyword("Feet")
GameSystem.RegisterItemKeyword("Waist")
GameSystem.RegisterItemKeyword("Shield")
GameSystem.RegisterItemKeyword("Implement")
GameSystem.RegisterItemKeyword("Wand")
GameSystem.RegisterItemKeyword("Whip")
GameSystem.RegisterItemKeyword("Light Weapon")
GameSystem.RegisterItemKeyword("Medium Weapon")
GameSystem.RegisterItemKeyword("Heavy Weapon")
GameSystem.RegisterItemKeyword("Polearm")
GameSystem.RegisterItemKeyword("Net")
GameSystem.RegisterItemKeyword("Bow")
GameSystem.RegisterItemKeyword("Ring")


GameSystem.RegisterAbilityCategorization{category = "Heroic Ability", grouping = "Heroic Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Villain Action", grouping = "Villain Actions"}
GameSystem.RegisterAbilityCategorization{category = "Malice", grouping = "Malice Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Signature Ability", grouping = "Signature Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Ability", grouping = "Common Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Trigger", grouping = "Triggers"}
GameSystem.RegisterAbilityCategorization{category = "Skill", grouping = "Common Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Basic Attack", grouping = "Common Abilities"}
GameSystem.RegisterAbilityCategorization{category = "Move", grouping = "Move"}
GameSystem.RegisterAbilityCategorization{category = "Hidden", grouping = "Common Abilities"}

GameSystem.ActionBarGroupings = {
    ["Heroic Abilities"] = 1,
    ["Malice Abilities"] = 2,
    ["Signature Abilities"] = 3,
    ["Common Abilities"] = 4,
    ["Triggers"] = 5,
}

function GameSystem.GetAbilityCategoryInfo(category)
    return GameSystem.abilityCategories[category] or {
        category = category,
        order = 1000,
    }
end

--set the default categorization.
ActivatedAbility.categorization = "Skill"



--the only type of resistance we need is damage reduction.
ResistanceEntry.types = {"Damage Reduction"}

--override available refresh options.
CharacterResource.RegisterRefreshOptions{
	{
		id = 'none',
		text = 'No usage limit',
		refreshDescription = 'always',
	},
	{
		id = 'turn',
		text = 'Per Turn',
		refreshDescription = 'each turn',
	},
	{
		id = 'round',
		text = 'Per Round',
		refreshDescription = 'each round',
	},
	{
		id = 'encounter',
		text = 'Per Encounter',
		refreshDescription = 'each encounter',
	},
	{
		id = 'long',
		text = 'Per Rest',
		refreshDescription = 'on rest',
	},
	{
		id = 'never',
		text = 'Manual Refresh',
		refreshDescription = 'manually',
	},
	{
		id = 'unbounded',
		text = 'Unbounded',
		refreshDescription = 'unbounded',
	},
	{
		id = 'global',
		text = 'Global',
		refreshDescription = 'global',
	},
}

--always just use squares for measurements.
MeasurementSystem.systems = {
	MeasurementSystem.new{
        value = "Tiles",
        text = "Squares",
		unitName = "Squares",
        unitSingular = "Square",
        abbreviation = "",
        tileSize = 1,
	},
}

setting{
    id = "measurementsystem",
    description = "Measurement Units",
    storage = "preference",
    editor = "dropdown",
    default = "Tiles",
    enum = MeasurementSystem.systems,
}

dmhub.unitsPerSquare = 1


--default damage type is 'untyped' damage.
ActivatedAbilityBehavior.damageType = "untyped"

GameSystem.RegisterConditionRule{
	id = "unconscious",
	conditions = {"Unbalanced"},

	rule = function(targetCreature, modifiers)
		return targetCreature:MaxHitpoints(modifiers) <= targetCreature.damage_taken
	end,
}

local g_abilitySymbols = {
    {
        name = "Used Ability",
        type = "ability",
        desc = "The ability used",
    },
    {
        name = "Cast",
        type = "cast",
        desc = "Casting information for the ability",
    }
}

TriggeredAbility.RegisterTrigger{
    id = "inflictcondition",
    text = "Condition Applied",
    symbols = {
        condition = {
            name = "Condition",
            type = "string",
            desc = "The name of the condition applied.",
        },
        attacker = {
            name = "Attacker",
            type = "creature",
            desc = "The attacking creature. Only valid if Has Attacker is true.",
        },
        hasattacker = {
            name = "Has Attacker",
            type = "boolean",
            desc = "True if a known creature inflicted the condition.",
        },
    }
}

TriggeredAbility.RegisterTrigger{
    id = "movethrough",
    text = "Move Through Creature",
    symbols = {
        target = {
            name = "Target",
            type = "creature",
            desc = "The creature being moved through.",
        },
    }
}

TriggeredAbility.RegisterTrigger{
    id = "teleport",
    text = "Teleport",
    symbols = {}
}

TriggeredAbility.RegisterTrigger{
    id = "leaveadjacent",
    text = "Creature Moved Away From",
    symbols = {
        movingcreature = {
            name = "Moving Creature",
            type = "creature",
            desc = "The creature moving away.",
        },
    },
}

TriggeredAbility.RegisterTrigger{
    id = "gaintempstamina",
    text = "Gain Temporary Stamina",
    symbols = {},
}

TriggeredAbility.RegisterTrigger{
    id = "castsignature",
    text = "Use Signature Attack or Area",
    symbols = g_abilitySymbols,
}

TriggeredAbility.RegisterTrigger{
    id = "useresource",
    text = "Use Resource",
    symbols = {
        resource = {
            name = "Resource",
            type = "string",
            desc = "The resource used.",
        },
        quantity = {
            name = "Quantity",
            type = "number",
            desc = "The number of resources used.",
        }
    }
}

TriggeredAbility.RegisterTrigger{
    id = "gainresource",
    text = "Gain Resource",
    symbols = {
        resource = {
            name = "Resource",
            type = "string",
            desc = "The resource used.",
        },
        quantity = {
            name = "Quantity",
            type = "number",
            desc = "The number of resources used.",
        }
    }
}

TriggeredAbility.RegisterTrigger{
    id = "useability",
    text = "Use an Ability",
    symbols = g_abilitySymbols,
}

TriggeredAbility.RegisterTrigger{
    id = "prestartturn",
    text = "Before Start of Turn",
    symbols = {},
}

GameSystem.OnEndCastActivatedAbility = function(casterToken, ability, options)
    if not ability:CountsAsRegularAbilityCast() then
        return
    end

    if options.abort then
        return
    end

    ability:FireUseAbility(casterToken, options)

	if ability.categorization == "Signature Ability" and (ability:HasKeyword("Area") or ability:HasKeyword("Strike")) then
		casterToken.properties:DispatchEvent("castsignature", {ability = ability, cast = options.symbols.cast})
	end
end

local friendlyFire = setting{
    id = "friendlyfire",
    description = "Friendly Fire",
    storage = "game",
	section = "game",
	editor = "check",
    dmonly = true,
    default = false,
}

function GameSystem.AllowTargeting(casterToken, targetToken, ability)
	if friendlyFire:Get() == false and ability:HasKeyword("Strike") and ability:HasKeyword("Area") and casterToken:IsFriend(targetToken) then
		return false
	end

	return true
end

CharSheet.DeregisterTab("Spells")

GameSystem.RegisterCreatureSizes{
	{
		name = "1T",
		tiles = 1,
		radius = 0.25,
	},
	{
		name = "1S",
		tiles = 1,
		radius = 0.4,
	},
	{
		name = "1M",
		tiles = 1,
		radius = 0.5,
		defaultSize = true,
	},
	{
		name = "1L",
		tiles = 1,
		radius = 0.6,
	},
	{
		name = "2",
		tiles = 2,
		radius = 0.95,
	},
	{
		name = "3",
		tiles = 3,
		radius = 1.45,
	},
	{
		name = "4",
		tiles = 4,
		radius = 2.0,
	},
	{
		name = "5",
		tiles = 5,
		radius = 2.5,
	},
    {
		name = "6",
		tiles = 6,
		radius = 3,
	},

}

Race.size = "1M"

--override the default type for damage resistance.
ResistanceEntry.apply = 'Damage Reduction'

GameSystem.TierNames = {
	"11 or lower",
	"12-16",
	"17+",
}

GameSystem.abilitiesHaveAttribute = false
GameSystem.abilitiesHaveDuration = false

GameSystem.minionsPerSquad = 4
GameSystem.minionsPerSquadText = "four"

GameSystem.GameMasterShortName = "Director"
GameSystem.GameMasterLongName = "Director"

CharacterModifier.DeregisterType("Armor Class Calculation")
CharacterModifier.DeregisterType("Attack Attribute")
CharacterModifier.DeregisterType("Custom Spellcasting")
CharacterModifier.DeregisterType("Damage Multiplier After Save")
CharacterModifier.DeregisterType("Grant Spell List")
CharacterModifier.DeregisterType("Grant Spells")
CharacterModifier.DeregisterType("Innate Spellcasting")
CharacterModifier.DeregisterType("Modify Damage")
CharacterModifier.DeregisterType("Multiple Attacks")
CharacterModifier.DeregisterType("Rolls Attacking Us")
CharacterModifier.DeregisterType("Spellcasting")

ActivatedAbility.SuppressType("Attack")
ActivatedAbility.SuppressType("Cast Spell")
ActivatedAbility.SuppressType("Contested Attack")
ActivatedAbility.SuppressType("Forced Movement")
ActivatedAbility.SuppressType("Saving Throw")

function TriggeredAbility.DeregisterTrigger(triggerid)
	for i,entry in ipairs(TriggeredAbility.triggers) do
		if entry.id == triggerid then
            table.remove(TriggeredAbility.triggers, i)
			break
		end
	end
end

TriggeredAbility.DeregisterTrigger("hit")

TriggeredAbility.RegisterTrigger{
    id = "targetwithability",
    text = "Target With Ability",
    symbols = {
        ability = {
            name = "Used Ability",
            type = "ability",
            desc = "The ability used.",
        },
        target = {
            name = "Target",
            type = "creature",
            desc = "The target creature.",
        }
    },
}



TriggeredAbility.RegisterTrigger{
    id = "losehitpoints",
    text = "Take Damage",
    symbols = {
        damage = {
            name = "Damage",
            type = "number",
            desc = "The amount of damage taken when triggering this event.",
        },
        rawdamage = {
            name = "Raw Damage",
            type = "number", 
            desc = "The amount of damage taken before any immunities or damage reduction.",
        },
        damagetype = {
            name = "Damage Type",
            type = "text",
            desc = "The type of damage taken when triggering this event.",
        },
        damageimmunity = {
            name = "Damage Immunity",
            type = "boolean",
            desc = "True if the damage was reduced or increased due to a damage immunity or weakness.",
        },
        keywords = {
            name = "Keywords",
            type = "set",
            desc = "The keywords used to apply the damage.",
        },
        surges = {
            name = "Surges",
            type = "number",
            desc = "The number of surges used for this damage.",
        },
        edges = {
            name = "Edges",
            type = "number",
            desc = "The number of edges used for this damage.",
        },
        banes = {
            name = "Banes",
            type = "number",
            desc = "The number of banes used for this damage.",
        },
        attacker = {
            name = "Attacker",
            type = "creature",
            desc = "The attacking creature. Only valid if Has Attacker is true.",
        },
        hasattacker = {
            name = "HasAttacker",
            type = "boolean",
            desc = "True if the damage has an attacker.",
        },
        hasability = {
            name = "HasAbility",
            type = "boolean",
            desc = "True if the damage has an ability.",
        },
        ability = {
            name = "Ability",
            type = "ability",
            desc = "The ability used.",
        },
    },

    examples = {
        {
            script = "damage > 8 and (damage type is slashing or damage type is piercing)",
            text = "The triggered ability only activates if more than 8 damage was done and the damage was slashing or piercing damage."
        }
    },
}

TriggeredAbility.RegisterTrigger{
    id = "dealdamage",
    text = "Damage an Enemy",
    symbols = {
        {
            name = "Damage",
            type = "number",
            desc = "The amount of damage dealt.",
        },
        {
            name = "Damage Type",
            type = "text",
            desc = "The type of damage dealt.",
        },
        {
            name = "Keywords",
            type = "set",
            desc = "The keywords used to apply the damage.",
        },
        {
            name = "Target",
            type = "creature",
            desc = "The target creature.",
        },
        {
            name = "Surges",
            type = "number",
            desc = "The number of surges applied to the damage.",
        },
        {
            name = "Edges",
            type = "number",
            desc = "The number of edges applied to the triggering damage ability.",
        },
        {
            name = "Banes",
            type = "number",
            desc = "The number of banes applied to the triggering damage ability.",
        },
        {
            name = "HasAbility",
            type = "boolean",
            desc = "True if the damage has an ability associated with it.",
        },
        {
            name = "Ability",
            type = "ability",
            desc = "The ability used to deal the damage. Only valid if HasAbility is true.",
        }
    }
}

TriggeredAbility.RegisterTrigger{
    id = "rollpower",
    text = "Roll Power",
    symbols = {
        {
            name = "Natural Roll",
            type = "number",
            desc = "The dice roll without any modifiers.",
        },
        {
            name = "Surges",
            type = "number",
            desc = "The number of surges used (across all targets).",
        },
        {
            name = "Tier One",
            type = "boolean",
            desc = "True if there was a tier one result (on at least one target).",
        },
        {
            name = "Tier Two",
            type = "boolean",
            desc = "True if there was a tier two result (on at least one target).",
        },
        {
            name = "Tier Three",
            type = "boolean",
            desc = "True if there was a tier three result (on at least one target).",
        },
        {
            name = "Ability",
            type = "ability",
            desc = "The ability used for the Power Roll.",
        },
    }
}

--redefine hitpoints as stamina.
CustomAttribute.RegisterAttribute{ id = "hitpoints", text = "Stamina", attributeType = "number", category = "Basic Attributes"}
CustomAttribute.DeregisterAttribute("armorClass")
CustomAttribute.DeregisterAttribute("initiativeBonus")
CustomAttribute.DeregisterAttribute("proficiencyBonus")
CustomAttribute.DeregisterAttribute("spellLevel")
CustomAttribute.DeregisterAttribute("spellcastingClasses")
CustomAttribute.DeregisterAttribute("spellsaveddc")
CustomAttribute.DeregisterAttribute("spellattackmod")

GameSystem.encumbrance = false