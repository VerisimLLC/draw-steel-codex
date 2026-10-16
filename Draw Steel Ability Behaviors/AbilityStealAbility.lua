local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityStealAbilityBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityStealAbilityBehavior
ActivatedAbilityStealAbilityBehavior = RegisterGameType("ActivatedAbilityStealAbilityBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityStealAbilityBehavior.summary = "Steal Ability"

ActivatedAbility.RegisterType
{
	id = 'stealAbility',
	text = 'Steal Ability',
	createBehavior = function()
		return ActivatedAbilityStealAbilityBehavior.new{
            stacks = 1,
		}
	end
}

--- Formats a characteristic value as it reads after a "+" in a roll or tier: "+ 3", "- 1".
--- @param value number
--- @return string
local function SignedBonus(value)
    if value < 0 then
        return "- " .. tostring(-value)
    end
    return "+ " .. tostring(value)
end

--True if text has a characteristic letter (M, A, R, I or P) at i that is a whole word.
--- @param text string
--- @param i integer
--- @return boolean
local function CharacteristicLetterAt(text, i)
    return string.find(string.sub(text, i, i), "^[MARIP]$") ~= nil
        and string.find(string.sub(text, i + 1, i + 1), "^%a$") == nil
end

--- Rewrites each "+ M", "+ M or A" or "+ R, I, or P" in tier text as "+ N", where N is the
--- owner's value for that characteristic (the highest of them when several are listed).
--- @param text string
--- @param owner creature
--- @return string
local function BakeTierCharacteristics(text, owner)
    local out = {}
    local pos = 1
    while true do
        local plusStart, plusEnd = string.find(text, "%+%s*", pos)
        if plusStart == nil then
            break
        end

        local best = nil
        local cursor = plusEnd + 1
        local lastLetter = nil
        while CharacteristicLetterAt(text, cursor) do
            local attrid = GameSystem.AttributeByFirstLetter[string.lower(string.sub(text, cursor, cursor))]
            if attrid ~= nil then
                local value = owner:AttributeMod(attrid)
                if best == nil or value > best then
                    best = value
                end
            end
            lastLetter = cursor
            local _, sepEnd = string.find(text, "^%s*,?%s*or%s+", cursor + 1)
            if sepEnd == nil then
                _, sepEnd = string.find(text, "^%s*,%s*", cursor + 1)
            end
            if sepEnd == nil then
                break
            end
            cursor = sepEnd + 1
        end

        if best ~= nil and lastLetter ~= nil then
            out[#out+1] = string.sub(text, pos, plusStart - 1) .. SignedBonus(best)
            pos = lastLetter + 1
        else
            out[#out+1] = string.sub(text, pos, plusEnd)
            pos = plusEnd + 1
        end
    end
    out[#out+1] = string.sub(text, pos)
    return table.concat(out)
end

--- Replaces the characteristic in a stolen ability's power roll and damage tiers with the
--- original owner's value, so the thief rolls "using their bonus" (Shadow "I Am You").
--- Handles any roll whose bonus names a characteristic: "2d10 + Agility", "2d10 + Might or
--- Agility" and the monsters' "2d10 + Highest Characteristic".
--- @param ability ActivatedAbility the copied ability (edited in place)
--- @param owner creature the creature the ability was copied from
function ActivatedAbilityStealAbilityBehavior.BakeTargetBonus(ability, owner)
    for _, behavior in ipairs(ability:try_get("behaviors", {})) do
        if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            ---@cast behavior ActivatedAbilityPowerRollBehavior
            --The owner's bonus: everything in the roll besides the dice, evaluated on them.
            local value = behavior:GetRollCharacteristicValue(owner)
            local dice = string.match(behavior:try_get("roll", ""), "%d*d%d+")
            if value ~= nil and dice ~= nil then
                behavior.roll = dice .. " " .. SignedBonus(value)
                --The roll no longer names a characteristic; keep answering with the owner's
                --value for power-roll modifiers that ask which characteristic was rolled.
                behavior.bakedRollCharacteristic = value
            end

            local tiers = behavior:try_get("tiers", {})
            for i, tier in ipairs(tiers) do
                tiers[i] = BakeTierCharacteristics(tier, owner)
            end
        end
    end
end

function ActivatedAbilityStealAbilityBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Ability Filter:",
        },
        gui.GoblinScriptInput{
            value = self:try_get("abilityFilter", ""),
            change = function(element)
                self.abilityFilter = element.value
            end,

            documentation = {
                help = "This GoblinScript is used to determine if this modifier filters an ability. If the result is true, the ability will be available, if it is false, the ability will be suppressed.",
                output = "boolean",
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is affected by this modifier",
                symbols = {
                    ability = {
                        name = "Ability",
                        type = "ability",
                        desc = "The ability that is being checked for availability.",
                        examples = {
                            "Ability.Name = 'Hide'",
                            "Ability.Keywords has 'Fire'",
                        },
                    },
                    caster = {
                        name = "Caster",
                        type = "caster",
                        desc = "The original caster of the ability.",
                        examples = {
                            "Caster.Name = 'Bob'",
                            "Caster.Level > 5",
                        },
                    },
                    usedability = {
                        name = "Used Ability",
                        type = "ability",
                        desc = "The ability that triggered this steal, if fired from a triggered ability.",
                        examples = {
                            "Ability.Name = Used Ability.Name",
                        },
                    },
                }
            }
        }
    }

    result[#result+1] = gui.Check{
        text = "Roll with the target's characteristic",
        value = self:try_get("useTargetBonus", false),
        halign = "left",
        hover = gui.Tooltip("The stolen ability's power roll and damage use the characteristic of the creature it was taken from instead of the thief's."),
        change = function(element)
            self.useTargetBonus = element.value
        end,
    }

    self:OngoingEffectEditor(parentPanel, result)
	return result
end

--Retained as a thin alias: the implementation now lives in ActivatedAbility so the
--invoke behavior's "chooseClassAbility" mode can share it. Existing callers and any
--saved content referencing this name keep working unchanged.
function ActivatedAbilityStealAbilityBehavior.ShowChoiceDialog(choices, dialogOptions, casterToken)
	return ActivatedAbility.ShowAbilityChoiceDialog(choices, dialogOptions, casterToken)
end


--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets {loc: Loc, token: CharacterToken}[] Steal Ability targets creatures, so every target carries a token.
--- @param options table
function ActivatedAbilityStealAbilityBehavior:Cast(ability, casterToken, targets, options)
    if self:try_get("ongoingEffect") == nil then
        printf("STEAL ABILITY:: NO EFFECT")
        return
    end
    
    local results = {}
    local filter = self:try_get("abilityFilter", "")

    for _, target in ipairs(targets) do
        local targetCreature = target.token.properties
        local candidateAbilities = targetCreature:GetActivatedAbilities{ characterSheet = true }
        for _,a in ipairs(candidateAbilities) do
            local passesFilter = true
            if filter ~= "" then
                local symbols = {
                    ability = a,
                    caster = casterToken.properties,
                    usedability = options ~= nil and options.symbols ~= nil and options.symbols.usedability or nil,
                }
                passesFilter = GoblinScriptTrue(ExecuteGoblinScript(filter, targetCreature:LookupSymbol(symbols), 0, "Steal Ability Filter"))
            end

            if passesFilter then
                local synth = DeepCopy(a)
                synth.stolenFrom = target.token.charid
                if self:try_get("useTargetBonus", false) then
                    ActivatedAbilityStealAbilityBehavior.BakeTargetBonus(synth, targetCreature)
                end

                results[#results+1] = synth
            end
        end
    end

    local chosenAbility = nil
    chosenAbility = ActivatedAbilityStealAbilityBehavior.ShowChoiceDialog(results, {
        title = "Steal Ability",
        buttonText = "Steal",
    }, casterToken)
    if chosenAbility == nil then
        return
    end

    --Marks this copy as a new arrival so the action bar flags it with the red "new" dot.
    chosenAbility.stolenStamp = dmhub.GenerateGuid()

    local casterInfo = {
        tokenid = casterToken.charid
    }

    if casterToken.properties ~= nil then
        casterToken:ModifyProperties{
            description = "Steal Ability",
            execute = function()
                local newEffect = casterToken.properties:ApplyOngoingEffect(self.ongoingEffect, self:try_get("duration"), casterInfo, {
                    stolenAbility = chosenAbility,
                    untilEndOfTurn = self.durationUntilEndOfTurn,
                })
            end
        }
    end

end 