local mod = dmhub.GetModLoading()

--this resets the game rules, allowing us to start from scratch and define our system.
GameSystem.ClearRules()

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

--what the basic rolls look like in our system.
GameSystem.BaseAttackRoll = "1d20"
GameSystem.BaseSkillRoll = "1d20"
GameSystem.BaseSavingThrowRoll = "1d20"
GameSystem.FlatRoll = "1d20"

--whether this type of game uses boons and banes as a concept.
GameSystem.UseBoons = false
GameSystem.AllowBoonsForRoll = function(options)
	--can use options.type to query the roll type in here if we want to allow boons for a roll.
	return false
end

--if this is true, then if a roll ever has e.g. 2d12-1d12 then it will normalize to 1d12.
GameSystem.CombineNegativesForRolls = false

GameSystem.CalculateDeathSavingThrowRoll = function(creature)
    return "1d20"
end

--the 'default' value of attributes. What they will be initialized to by default.
CharacterAttribute.baseValue = 10

--This controls the calculation for the modifier of an attribute. e.g. an attribute of 17 gives a modifier of +3
GameSystem.CalculateAttributeModifier = function(attributeInfo, attributeValue)
	local n = attributeValue
	if (n%2 == 1) then
		n = n-1
	end

	return math.tointeger((n/2) - 5)
end

--how initiative is controlled!
GameSystem.BaseInitiativeRoll = "1d20"
GameSystem.LowerInitiativeIsFaster = false

--how the initiative modifier is calculated. Important: If you remove dexterity then also change this!
GameSystem.CalculateInitiativeModifier = function(creature)
	return creature:GetAttribute('dex'):Modifier()
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
GameSystem.BaseArmorClass = 10

--the attribute that modifies armor class.
GameSystem.ArmorClassModifierAttrId = "dex"

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
--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMRules.lua:138
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
--]==]


--in 5e, abilities don't have "categorizations" attached to them.
GameSystem.hasAbilityCategorization = false
GameSystem.abilityCategories = {}

--in 5e, abilities don't have special "keywords" attached to them.
GameSystem.hasAbilityKeywords = false
GameSystem.abilityKeywords = {}

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

--the attributes available in our system.
GameSystem.RegisterAttribute{
	id = "str",
	description = "Strength",
	order = 10,
}

GameSystem.RegisterAttribute{
	id = "dex",
	description = "Dexterity",
	order = 20,
}

GameSystem.RegisterAttribute{
	id = "con",
	description = "Constitution",
	order = 30,
}

GameSystem.RegisterAttribute{
	id = "int",
	description = "Intelligence",
	order = 40,
}

GameSystem.RegisterAttribute{
	id = "wis",
	description = "Wisdom",
	order = 50,
}

GameSystem.RegisterAttribute{
	id = "cha",
	description = "Charisma",
	order = 60,
}

GameSystem.RegisterSavingThrow{
	id = "str",
	attrid = "str",
	description = "Strength",
	order = 10,
}

GameSystem.RegisterSavingThrow{
	id = "dex",
	attrid = "dex",
	description = "Dexterity",
	order = 20,
}

GameSystem.RegisterSavingThrow{
	id = "con",
	attrid = "con",
	description = "Constitution",
	order = 30,
}

GameSystem.RegisterSavingThrow{
	id = "int",
	attrid = "int",
	description = "Intelligence",
	order = 40,
}

GameSystem.RegisterSavingThrow{
	id = "wis",
	attrid = "wis",
	description = "Wisdom",
	order = 50,
}

GameSystem.RegisterSavingThrow{
	id = "cha",
	attrid = "cha",
	description = "Charisma",
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

--failed save/passed save. When calling RegisterRollType use applyto to add to these id's.
GameSystem.RegisterApplyToTargets{
	id = "failed_save",
	text = "Targets Who Failed Saving Throw",
}

GameSystem.RegisterApplyToTargets{
	id = "passed_save",
	text = "Targets Who Passed Saving Throw",
}

print("APPLYTO:: INIT", #GameSystem.ApplyToTargetsList, "/", GameSystem.ApplyToTargetsList)

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

		--this is called after we trigger events saying we are attacking. The target creature's armor class may
		--have been updated as a result, so we update the armor class outcome to reflect that.
		rollRules.UpdateOutcomesAfterEvents = function(self, castingCreature, targetCreature)
			self.outcomes[2].value = targetCreature:ArmorClass()
		end
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
            color = "#00ff00",
            degree = 1,
            success = true,
        }

        rollRules:AddOutcome{
            value = 999, --this value is too high to get under normal circumstances, only available with a nat20.
            criticalRoll = true, --this will be chosen automatically on a 'critical' roll (normally a nat20)
            outcome = "Critical Success",
            color = "#00ff00",
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
--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMRules.lua:496
function character:BaseProficiencyBonus()
	local n = self:CharacterLevel() - 1
	n = n - n%4
	local baseProficiency = 2 + n/4
	return self:CalculateAttribute("proficiencyBonus", baseProficiency)
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMRules.lua:504
function monster:BaseProficiencyBonus()
	local cr = (tonumber(self:try_get("cr", 0)) or 0)
	local n = cr - 1
	n = n - n%4
	local baseProficiency = 2 + math.max(0, n/4)
	return self:CalculateAttribute("proficiencyBonus", baseProficiency)
end
--]==]

--The way in which proficiency bonus is calculated from a proficiency level.
GameSystem.CalculateProficiencyBonus = function(creature, proficiencyLevel)

	if proficiencyLevel == nil then
        --we got this error condition sometimes, so this diagnostic code is here to send a trace of it to the cloud so DMHub programmers can work out why.
		dmhub.CloudError("nil proficiencyLevel: " .. traceback())
		return 0
	end


    if proficiencyLevel.multiplier == 0 then
        return 0
    end

    return math.floor(creature:BaseProficiencyBonus()*proficiencyLevel.multiplier)
end

--proficiency levels.
GameSystem.RegisterProficiencyLevel{
	id = "none",
	text = "Not Proficient",
	multiplier = 0,
	verboseDescription = tr("You are not proficient in %s."),
}

GameSystem.RegisterProficiencyLevel{
	id = "half",
	text = "Half Proficient",
	multiplier = 0.5,
	verboseDescription = tr("You may apply half your proficiency bonus to a skill check with %s."),
}

GameSystem.RegisterProficiencyLevel{
	id = "proficient",
	text = "Proficient",
	multiplier = 1,
	verboseDescription = tr("You are proficient with %s."),
}

GameSystem.RegisterProficiencyLevel{
	id = "expertise",
	text = "Expertise",
    color = "#ff00ff",
	multiplier = 2,

    --TODO: make a way to make the color of this configurable.
	characterSheetLabel = "E",
	verboseDescription = tr("You may apply double your proficiency bonus to skill checks with %s."),
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

--We can register attributes that can be modified by Modify Attribute like this.
GameSystem.RegisterModifiableAttribute{
    id = "ignoreoffhandpenalty",
    text = "Ignore Offhand Damage Penalty",
    attributeType = "number",
    category = "Combat",
}

--This is used to tell if we ignore off hand weapon penalties.
--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMRules.lua:601
function GameSystem.IgnoreOffhandWeaponPenalty(creature, weapon)
	return creature:CalculateAttribute('ignoreoffhandpenalty', 0) > 0
end
--]==]

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
    return string.format(tr([[<size=120%%><smallcaps><b>Hit Points</b></smallcaps></size>
<b>Hit Dice:</b> 1d%d per %s level
<b>Hit Points at 1st Level:</b> %d + your Constitution modifier
<b>Hit Points at Higher Levels:</b> 1d%d (or %d) + your Constitution modifier per %s level after 1st]]),
        class.hit_die, string.lower(class.name), class.hit_die, class.hit_die, math.ceil(class.hit_die/2) + 1, string.lower(class.name))
end

--whether rolling for hitpoints is something characters can do when they level up.
GameSystem.allowRollForHitpoints = true

--Hitpoints are not allowed to be negative, they won't fall below zero.
GameSystem.allowNegativeHitpoints = false

--the number of hitpoints gained each level when using fixed hitpoints
GameSystem.FixedHitpointsForLevel = function(class, firstLevel)
    if firstLevel then
        return class.hit_die
    else
        return round(1 + class.hit_die/2)
    end
end

--additional hitpoints when leveling up aside from what the class provides.
GameSystem.BonusHitpointsForLevel = function(creature)
    return creature:AttributeMod("con")
end

--how we briefly describe what the bonus hitpoints per level is calculated from.
GameSystem.bonusHitpointsForLevelRulesText = tr("Con. Mod.")

--does this game system use hit dice?
GameSystem.haveHitDice = true

--does this game system have temporary hitpoints?
GameSystem.haveTemporaryHitpoints = true

--do races list features for each and every level?
GameSystem.racesHaveLeveling = true

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

--Make it so if the creature has 0 hitpoints it gets the unconscious condition, along with incapacitated and prone.
GameSystem.RegisterConditionRule{
	id = "unconscious",
	conditions = {"Unconscious", "Incapacitated", "Prone"},

	rule = function(targetCreature, modifiers)
		local maxHp = targetCreature:MaxHitpoints(modifiers) or 0
		return maxHp <= targetCreature:try_get("damage_taken", 0)
	end,
}

--This is called when we finish casting an ability or spell. Can use it to do any interesting triggers.
GameSystem.OnEndCastActivatedAbility = function(casterToken, ability, options)
end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMRules.lua:1173
function GameSystem.AllowTargeting(casterToken, targetToken, ability)
	return true
end
--]==]

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

TriggeredAbility.RegisterTrigger{
    id = "attacked",
    text = "Attacked",

    symbols = {
        outcome = {
            name = "Outcome",
            type = "text",
            desc = string.format("The outcome of the attack. Possible values: %s", GameSystem.PrettyAttackOutcomes()),
        },
        roll = {
            name = "Roll",
            type = "number",
            desc = "The total of the roll to hit.",
        },
        attack = {
            name = "Attack",
            type = "attack",
            desc = "The attack used.",
        },
        attacker = {
            name = "Attacker",
            type = "creature",
            desc = "The creature attacking.",
        },
    },

    examples = {
        {
            script = "Outcome is Miss and Roll < Armor Class - 5",
            text = "The ability only triggers on a miss where the attack roll was more than 5 below what was required to hit.",
        },
        {
            script = "Outcome is Critical",
            text = "The ability only triggers on a critical hit.",
        },
    },
}


TriggeredAbility.RegisterTrigger{
	id = "miss",
	text = "Miss an Attack",
       symbols = {
		outcome = {
			name = "Outcome",
			type = "text",
			desc = string.format("The outcome of the attack. Possible values: %s", GameSystem.PrettyAttackOutcomes()),
		},
		degree = {
			name = "Degree",
			type = "number",
			desc = "The degree to which the attack missed. 1 is a regular miss, 2 is a fumble. Different game systems may define this differently.",
		},
		attack = {
			name = "Attack",
			type = "attack",
			desc = "The attack used.",
		},
		target = {
			name = "Attacker",
			type = "creature",
			desc = "The creature targeted with the attack.",
		},
       },
}

TriggeredAbility.RegisterTrigger{
    id = "hit",
    text = "Damaged by Attack",
    symbols = {
        attacker = {
            name = "Attacker",
            type = "creature",
            desc = "The attacking creature.",
        },
        attack = {
            name = "Attack",
            type = "attack",
            desc = "The attack used.",
        },
    },
}

GameSystem.GameMasterShortName = "DM"
GameSystem.GameMasterLongName = "Dungeon Master"
