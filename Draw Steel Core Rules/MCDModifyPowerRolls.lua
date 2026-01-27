local mod = dmhub.GetModLoading()

CharacterModifier.DeregisterType("d20")

CharacterModifier.displayCondition = ""

local g_powerRollTypes = {
    {
        id = "all",
        text = "All Our Power Rolls",
    },
    {
        id = "ability_power_roll",
        text = "Ability Rolls",
    },
    {
        id = "test_power_roll",
        text = "Tests",
    },
        {
        id = "opposed_power_roll",
        text = "Opposed Tests",
    },
    {
        id = "resistance_power_roll",
        text = "Resistance Rolls",
    },
    {
        id = "project_roll",
        text = "Project Roll",
    },
    {
        id = "enemy_ability_power_roll",
        text = "Enemy Ability Rolls vs Us",
    },
}

local function RollTypeMatches(modifier, rollType)
    if modifier.rollType == "all" and rollType ~= "enemy_ability_power_roll" then
        return true
    end

    return rollType == modifier.rollType
end


CharacterModifier.RegisterType('power', "Modify Power Rolls")

--Something like Shift 2/3/4 will become {"Shift 2", "Shift 3", "Shift 4}
local function BreakTextIntoTiers(text)

    --first handle the possibility of something like No Effect // Taunted (EoT) // Dazed (EoE)
    local match = regex.MatchGroups(text, "^(?<tier1>.*?)(\\s*//\\s*)(?<tier2>.*?)(\\s*//\\s*)(?<tier3>.*)$")
    if match ~= nil then
        return { match.tier1, match.tier2, match.tier3 }
    end

    local result = {"", "", ""}
    local pattern = "^(?<prefix>.*?)(?<tier1>\\d+)/(?<tier2>\\d+)/(?<tier3>\\d+)(?<postfix>.*)$"
    local match = regex.MatchGroups(text, pattern)

    while match ~= nil do

        result[1] = result[1] .. match.prefix .. match.tier1
        result[2] = result[2] .. match.prefix .. match.tier2
        result[3] = result[3] .. match.prefix .. match.tier3

        text = match.postfix
        match = regex.MatchGroups(text, pattern)
    end

    result[1] = result[1] .. text
    result[2] = result[2] .. text
    result[3] = result[3] .. text

    return result
end

local AppendTieredText
AppendTieredText = function(tieredText, text)
    text = trim(text)
    if text == "" then
        return tieredText
    end

    local entries = string.split(text, ";")
    if entries ~= nil and #entries > 1 then
        for _,entry in ipairs(entries) do
            tieredText = AppendTieredText(tieredText, trim(entry))
        end

        return tieredText
    end

    local damageMatch = regex.MatchGroups(text, "^(?<damage>\\+?-?\\d+)\\s+(?<damageType>[a-zA-Z]+\\s+)?damage$")
    if damageMatch ~= nil then
        if damageMatch.damageType ~= nil then
            local damageType = trim(damageMatch.damageType)
            local existingDamageMatch = regex.MatchGroups(tieredText, "(?<prefix>.*?)(?<damage>\\+?-?\\d+)\\s+" .. damageType .. "damage(?<suffix>.*)$")
            if existingDamageMatch ~= nil then
                local totalDamage = tonumber(existingDamageMatch.damage) + tonumber(damageMatch.damage)
                return string.format("%s%d %s damage%s", existingDamageMatch.prefix, totalDamage, damageType, existingDamageMatch.suffix)
            end
        else
            local existingDamageMatch = regex.MatchGroups(tieredText, "(?<prefix>.*?)(?<damage>\\+?-?\\d+)\\s+damage(?<suffix>.*)$")
            if existingDamageMatch ~= nil then
                local totalDamage = tonumber(existingDamageMatch.damage) + tonumber(damageMatch.damage)
                return string.format("%s%d damage%s", existingDamageMatch.prefix, totalDamage, existingDamageMatch.suffix)
            end
        end
    end

    return string.format("%s; %s", tieredText, text)
end

local g_powerRollsAbilityAdditionalSymbols = {
	ability = {
		name = "Ability",
		type = "ability",
		desc = "The ability being used for this roll.",
	},
	target = {
		name = "Target",
		type = "creature",
		desc = "The creature that is being targeted with this ability.",
	},
    caster = {
		name = "Caster",
		type = "creature",
		desc = "The creature that is casting the ability.",
	},
}

local g_powerRollSymbols = DeepCopy(CharacterModifier.defaultHelpSymbols)
for k,v in pairs(g_powerRollsAbilityAdditionalSymbols) do
    g_powerRollSymbols[k] = v
end

function CharacterModifier:CheckRollRequirement(rollInfo, enabledModifiers, rollProperties)
    local requirement = self:try_get("rollRequirement", "none")
    if requirement == "none" then
        return true
    end

    local edges = rollInfo.boons or 0
    local banes = rollInfo.banes or 0

    if requirement == "bane" then
        return banes > edges and edges < 2
    elseif requirement == "doublebane" then
        return banes >= 2 and edges <= 0
    elseif requirement == "edge" then
        return edges > banes and banes < 2
    elseif requirement == "doubleedge" then
        return edges >= 2 and banes <= 0
    elseif requirement == "nobane" then
        return banes <= 0
    elseif requirement == "noedge" then
        return edges <= 0
    elseif requirement == "skilled" or requirement == "unskilled" then
        local hasSkill = false
        for _,mod in ipairs(enabledModifiers) do
            if mod.modifier and mod.modifier.name == "Skilled" then
                hasSkill = true
                break
            end
        end

        if requirement == "skilled" then
            return hasSkill
        else
            return not hasSkill
        end
    elseif requirement == "surges" then
        if rollProperties:try_get("surges", 0) > 0 then
            return true
        else
            for _, target in ipairs(rollProperties:try_get("multitargets", {})) do
                if target and target.surges and target.surges > 0 then
                    return true
                end
            end
            return false
        end
    end

    return true
end

CharacterModifier.TypeInfo.power = {

    init = function(modifier)
        modifier.rollType = "ability_power_roll"
        modifier.modtype = "none"
        modifier.activationCondition = false
        modifier.keywords = {}
    end,

    triggerOnUse = function(modifier, creature, modContext)
        if modifier:has_key("baseModifier") and (not modifier:try_get("gobefore", false)) and (not modifier:try_get("overrideBase", false)) then
            print("TRIGGER:: BASE GOES FIRST")
            CharacterModifier.TypeInfo.power.triggerOnUse(modifier.baseModifier, creature, modContext)
        end
		if modifier:try_get("hasCustomTrigger", false) and modifier:has_key("customTrigger") then
            local token = dmhub.LookupToken(creature)

            
            print("TRIGGER:: TRIGGER", token.charid)
			modifier.customTrigger:Trigger(modifier, creature, modifier:AppendSymbols{}, nil, modContext)
		end

        if modifier:has_key("baseModifier") and (modifier:try_get("gobefore", false)) and (not modifier:try_get("overridebase", false)) then
            print("TRIGGER:: BASE GOES LAST")
            CharacterModifier.TypeInfo.power.triggerOnUse(modifier.baseModifier, creature, modContext)
        end
	end,

    hintPowerRoll = function(self, creature, rollType, options)
        options = options or {}

        if self:has_key("baseModifier") and (not self:try_get("overrideBase", false)) then
            local baseResult = CharacterModifier.TypeInfo.power.hintPowerRoll(self.baseModifier, creature, rollType, options)
            if baseResult.result == false then
                return baseResult
            end
        end


        if (self.activationCondition == false) or (not RollTypeMatches(self, rollType)) then
            return {
                result = false,
                justification = {}
            }
        end

        if self:has_key("keywords") and self.rollType ~= "all" and options.ability ~= nil then
            local totalCount = 0
            local matchCount = 0
            local keywordFail = {}
            for keyword,_ in pairs(self.keywords) do
                totalCount = totalCount + 1
                if options.ability:HasKeyword(keyword) then
                    matchCount = matchCount + 1
                else
                    keywordFail[#keywordFail+1] = keyword
                end
            end

            if matchCount < totalCount and (matchCount == 0 or not self:try_get("matchAnyKeywords", false)) then
                return {
                    result = false,
                    justification = {string.format("Ability does not have the %s keyword", table.concat(keywordFail, " or "))},
                }
            end
        end

        if self:HasResourcesAvailable(creature) == false then
			return {
				result = false,
				justification = {"You have expended all uses of this ability."},
			}
		end

        if #self:try_get("skills", {}) > 0 and (rollType == "test_power_roll" or rollType == "opposed_power_roll") and options.skills == nil then
            --if this roll is relevant to certain skills but the dialog doesn't
            --have skills specified then we should set it to false.
            return {
                result = false,
                justification = {"Ensure this roll is using the correct skill to activate this modifier."}
            }
        end

        if self.activationCondition == true then
            return {
                result = true,
                justification = {}
            }
        end

		local lookupFunction = creature:LookupSymbol(self:AppendSymbols{
			ability = GenerateSymbols(options.ability),
			target = GenerateSymbols(options.target),
            title = options.title or "",
		})

        print("POWER ROLL:: OPTIONS:", options)

        return {
            result = GoblinScriptTrue(ExecuteGoblinScript(self.activationCondition, lookupFunction, 0, "Power Roll Activation Condition")),
            justification = {},
        }
    end,

    shouldShowInPowerRollDialog = function(self, creature, rollType, roll, options)

        if self:has_key("baseModifier") and (not CharacterModifier.TypeInfo.power.shouldShowInPowerRollDialog(self.baseModifier, creature, rollType, roll, options)) then
            return false
        end

        if self:try_get("attribute", "all") ~= "all" and (rollType == "test_power_roll" or rollType == "opposed_power_roll" or rollType == "resistance_power_roll") and options ~= nil then
            if self.attribute ~= options.attribute then
                return false
            end
        end

        if #self:try_get("skills", {}) > 0 and rollType == "test_power_roll" and options.skills ~= nil then
            local hasSkill = false
            for _,skillid in ipairs(self.skills) do
                for _,skillid2 in ipairs(options.skills) do
                    if skillid == skillid2 then
                        hasSkill = true
                        break
                    end
                end
            end

            if not hasSkill then
                return false
            end
        end

        if #self:try_get("skills", {}) > 0 and rollType == "opposed_power_roll" then
            if options.ability and options.ability.behaviors then
                local behaviors = options.ability.behaviors or {}
                for _, behavior in ipairs(behaviors) do
                    if behavior.typeName == "ActivatedAbilityOpposedRollBehavior" then
                        local hasSkill = false
                        local skillInfo
                        for _,skillid in pairs(behavior.attackAttributes) do
                            for _, modSkillId in pairs(self.skills) do
                                if skillid == modSkillId then
                                    skillInfo = skillid
                                    hasSkill = true
                                    break
                                end
                            end
                        end

                        if not hasSkill then
                            return false
                        end
                    end
                end
            end
        end

        if not RollTypeMatches(self, rollType) then
            return false
        end

        if not self:PassesFilter(creature) then
            return false
        end
            
        if self.displayCondition ~= "" then
            local lookupFunction = creature:LookupSymbol(self:AppendSymbols{
                ability = GenerateSymbols(options.ability),
                target = GenerateSymbols(options.target),
                caster = GenerateSymbols(options.caster),
                title = options.title or "",
            })

            if not GoblinScriptTrue(ExecuteGoblinScript(self.displayCondition, lookupFunction, 0, "Power Roll Activation Condition")) then
                return false
            end
        end

        return true
    end,

    modifyPowerRoll = function(self, creature, rollType, roll, options)
        if self:has_key("baseModifier") and (not self:try_get("overrideBase", false)) then
            roll = CharacterModifier.TypeInfo.power.modifyPowerRoll(self.baseModifier, creature, rollType, roll, options)
        end

        if self.modtype == "none" or self.modtype == "suppresseffects" then
            return roll
        end

        print("MODIFY:: MOD ROLL", self.modtype)

        if self.modtype == "appendroll" or self.modtype == "replaceroll" then 
            local newRoll = dmhub.EvalGoblinScript(self:try_get("replaceText"), creature:LookupSymbol(), "Power Roll Replacement")
            
            --we only consider the "2d10 + xxx" part as the 'roll' to replace. Anything after that should be kept.
            local m = regex.MatchGroups(roll, "^(?<roll>2d10(?:\\s*[+-]\\s*\\d+)?)(?<suffix>.*)$")
            if m ~= nil then
                if self.modtype == "appendroll" then
                    roll = m.roll .. " + " .. newRoll .. m.suffix
                else
                    roll = newRoll .. m.suffix
                end
            else
                if self.modtype == "appendroll" then
                    roll = tostring(roll) .. " + " .. newRoll
                else
                    roll = newRoll
                end
            end
            return roll
        end

        local modType = ActivatedAbilityPowerRollBehavior.s_modificationTypesById[self.modtype]
        if modType.remove_edge or modType.ignore_edges then
            local m = regex.MatchGroups(roll, "^(?<prefix>.*?)(?<edge>\\d+)\\s+edge(?<suffix>.*)$")
            if m ~= nil then
                local val = tonumber(m.edge)
                if val > 0 then
                    val = val-1
                end

                if modType.ignore_edges then
                    val = 0
                end
                roll = m.prefix .. val .. " edge" .. m.suffix
            end
        elseif modType.remove_bane or modType.ignore_banes then
            local m = regex.MatchGroups(roll, "^(?<prefix>.*?)(?<bane>\\d+)\\s+bane(?<suffix>.*)$")
            if m ~= nil then
                local val = tonumber(m.bane)
                if val > 0 then
                    val = val-1
                end

                if modType.ignore_banes then
                    val = 0
                end
                roll = m.prefix .. val .. " bane" .. m.suffix
            end
        end

        return roll .. " " .. modType.mod
    end,

    buffOrDebuff = function(self, context)
        local modType = ActivatedAbilityPowerRollBehavior.s_modificationTypesById[self.modtype]
        local buffOrDebuff = modType.value
        if tonumber(buffOrDebuff) then
            if buffOrDebuff > 0 then
                return "buff"
            elseif buffOrDebuff < 0 then
                return "debuff"
            end
        end
    end,

    renderOnRoll = function(self, rollInfo, triggerInfo, targetPanel)
        if not targetPanel.data.init then

            local description = ""
            local modType = ActivatedAbilityPowerRollBehavior.s_modificationTypesById[self.modtype]
            if modType ~= nil and not modType.hideText then
                description = modType.text
            end

            local buffOrDebuff = modType.value

            --generate a good set of symbols to do any goblin scripts on.
            local token = nil
            if rollInfo.tokenid ~= nil then
                token = dmhub.GetTokenById(rollInfo.tokenid)
            end

            if token ~= nil and token.valid then
                local lookupFunction
                if triggerInfo ~= nil then
                    local triggerer = dmhub.GetTokenById(triggerInfo.charid)
                    local target = dmhub.GetTokenById(triggerInfo.targetid)

                    lookupFunction = token.properties:LookupSymbol(self:AppendSymbols{
                        triggerer = triggerer ~= nil and triggerer.valid and triggerer.properties,
                        target = target ~= nil and target.valid and target.properties,
                    })

                else
                    lookupFunction = token.properties:LookupSymbol()
                end

                local damageModifier = self:try_get("damageModifier", "")
                if damageModifier ~= "" then
                    local damageModifierType = self:try_get("damageModifierType", "none")
                    local damageStr = dmhub.EvalGoblinScript(damageModifier, lookupFunction, "Power Roll Damage Modifier")
                    local damage = safe_toint(damageStr)
                    if damage ~= nil then
                        damage = round(damage)
                        if description ~= "" then
                            description = description .. "\n"
                        end

                        description = string.format("%s%s%d damage", description, cond(damage > 0, "+", ""), damage)
                        buffOrDebuff = buffOrDebuff + damage
                    end
                end
            end


            if modType ~= nil and buffOrDebuff ~= nil then
                targetPanel:SetClass("good", buffOrDebuff > 0)
                targetPanel:SetClass("bad", buffOrDebuff < 0)
            end

            targetPanel.data.init = true
            local panel = gui.Panel{
                width = "100%",
                height = "100%",
                flow = "vertical",
                linger = function(element)
                    gui.Tooltip(string.format("<b>%s</b>\n%s\n%s", self.name, description, self:try_get("description", "")))(element)
                end,
                sometargets = function(element, value)
                    if not value then
                        if element.data.someTargets then
                            element.data.someTargets:SetClass("collapsed", true)
                        end
                    else
                        if not element.data.someTargets then
                            element.data.someTargets = gui.Label{
                                fontSize = 8,
                                color = Styles.textColor,
                                text = "*Some Targets",
                                width = "auto",
                                height = "auto",
                                vmargin = 1,
                                hpad = 4,
                                valign = "bottom",
                            }
                            element:AddChild(element.data.someTargets)
                        end

                        element.data.someTargets:SetClass("collapsed", false)
                    end
                end,
                data = {
                    someTargets = false,
                },
                gui.Label{
                    color = Styles.textColor,
                    tmargin = 2,
                    bmargin = 0,
                    hpad = 4,
                    valign = "top",
                    bold = true,
                    width = "100%",
                    height = "auto",
                    textWrap = false,
                    textOverflow = "ellipsis",
                    fontSize = 12,
                    minFontSize = 8,
                    text = self.name,
                },
                gui.Label{
                    color = Styles.textColor,
                    vmargin = 0,
                    hpad = 4,
                    valign = "top",
                    width = "100%",
                    height = "auto",
                    fontSize = 10,
                    text = description,
                },

            }

            targetPanel:AddChild(panel)
        end

        targetPanel:FireEventTree("render", self, rollInfo)
        
        --see if this modifier only applies to some of the targets.
        local sometargets = false

        if #rollInfo.properties.multitargets > 1 then
            for _,target in ipairs(rollInfo.properties.multitargets) do
                local found = false
                for _,modifierUsed in ipairs(target.modifiersUsed) do
                    if modifierUsed.name == self.name then
                        found = true
                        break
                    end
                end

                if not found then
                    sometargets = true
                    break
                end
            end
        end

        targetPanel:FireEventTree("sometargets", sometargets)
    end,

    modifyRollProperties = function(self, creature, rollProperties, targetCreature)
        if self:has_key("baseModifier") and (not self:try_get("overrideBase", false)) then
            CharacterModifier.TypeInfo.power.modifyRollProperties(self.baseModifier, creature, rollProperties, targetCreature)
        end

        if rollProperties.typeName ~= "RollPropertiesPowerTable" then
            return
        end

        rollProperties.tester = true

        local damageTypeMappings = self:try_get("damageTypeMappings")
        if damageTypeMappings ~= nil then
            if damageTypeMappings["all"] ~= nil then
                local mapto = damageTypeMappings["all"]
                damageTypeMappings = {}
                for _,damageType in ipairs(rules.damageTypesAvailable) do
                    damageTypeMappings[damageType] = mapto
                end
            end
            for i=1,#rollProperties.tiers do
                local tier = rollProperties.tiers[i]
                for k,v in pairs(damageTypeMappings) do
                    if k == "untyped" then
                        local m = regex.MatchGroups(tier, "^(?<prefix>.*?)(?<damage>\\d+)\\s+([a-zA-Z]+\\s+)?damage(?<suffix>.*)$")
                        if m ~= nil then
                            tier = m.prefix .. m.damage .. " " .. v .. " damage" .. m.suffix
                        end
                    else
                        tier = regex.ReplaceAll(tier, k .. " damage", v .. " damage")
                    end
                end

                rollProperties.tiers[i] = tier
            end
        end

        local triggerer = nil
        if self:try_get("_tmp_trigger") then
            local triggererToken = dmhub.GetTokenById(self._tmp_triggerCharid)
            if triggererToken ~= nil then
                triggerer = triggererToken.properties
            end
        end

        local lookupFunction = creature:LookupSymbol(self:AppendSymbols{
            triggerer = triggerer,
            target = GenerateSymbols(targetCreature),
        })

        local damageModifier = self:try_get("damageModifier", "")
        if damageModifier ~= "" then
            local damageModifierType = self:try_get("damageModifierType", "none")
            local damage = dmhub.EvalGoblinScript(damageModifier, lookupFunction, "Power Roll Damage Modifier")

            --local damage = ExecuteGoblinScript(damageModifier, lookupFunction, 0, "Power Roll Damage Modifier")
            if damage ~= "" and safe_toint(damage) ~= 0 then

                for i,tier in ipairs(rollProperties.tiers) do
                    if damageModifierType == "none" then
                        --add to existing damage
                        local match = regex.MatchGroups(tier, "(?<damage>\\d+)\\s+([a-zA-Z]+\\s+)?damage", {indexes = true})
                        if match ~= nil then
                            local index = match.damage.index
                            local length = match.damage.length

                            local before = string.sub(tier, 1, index-1)
                            local after = string.sub(tier, index+length)

                            local damageValue = round(safe_toint(match.damage.value))

                            if safe_toint(damage) ~= nil then
                                damageValue = round(damageValue + safe_toint(damage))
                                tier = string.format("%s%d%s", before, damageValue, after)
                            else
                                tier = string.format("%s%d + %s%s", before, damageValue, damage, after)
                            end

                            --printf("ROLL PROPERTIES: [%d]: %s -> %s", i, tier, rollProperties.tiers[i])
                        end
                    else
                        local extraDamage = string.format("%s %s damage", damage, damageModifierType)

                        --try to find existing damage and place after it if possible.
                        local match = regex.MatchGroups(tier, "^(?<prefix>.*?)(?<damage>\\d+\\s+([a-zA-Z]+\\s+)?damage)(?<suffix>.*)$")
                        if match ~= nil then
                            tier = string.format("%s%s; %s %s", match.prefix, match.damage, extraDamage, match.suffix)
                        else
                            --just put damage at the front.
                            tier = string.format("%d %s damage; %s", extraDamage, tier)
                        end
                    end

                    rollProperties.tiers[i] = tier
                end
            end
        end

        local damageMultiplier = self:try_get("damageMultiplier", "full")
        if damageMultiplier ~= "full" then
            for i,tier in ipairs(rollProperties.tiers) do
                local match = regex.MatchGroups(tier, "(?<damage>\\d+\\s+([a-zA-Z]+\\s+)?damage)", {indexes = true})
                if match ~= nil then
                    local index = match.damage.index
                    local length = match.damage.length

                    local before = string.sub(tier, 1, index+length-1)
                    local after = string.sub(tier, index+length)

                    rollProperties.tiers[i] = string.format("%s (half)%s", before, after)
                end
            end
        end

        for i,adjustment in ipairs(self:try_get("adjustments", {})) do
            local pattern = "^(?<prefix>.*)(?<type>" .. adjustment.type .. ")\\s+(?<value>\\d+)(?<postfix>.*)$"

            for j,tier in ipairs(rollProperties.tiers) do
                local match = regex.MatchGroups(tier, pattern)
                if match ~= nil then
                    local adj = ExecuteGoblinScript(adjustment.value, lookupFunction, 1, "Determine adjustment")
                    local value = safe_toint(match.value)
                    local newValue = math.max(0, value + (adj or 0))
                    rollProperties.tiers[j] = string.format("%s%s %d%s", match.prefix, match.type, newValue, match.postfix)
                end
            end
        end

        local surges = self:try_get("surges", "")
        if surges ~= "" then
            local addSurges = ExecuteGoblinScript(surges, lookupFunction, 0, "Power Roll Surges")
            rollProperties.surges = rollProperties:try_get("surges", 0) + addSurges

            if self:try_get("surgesCanBeKept", false) then
                rollProperties.nonwastedSurges = rollProperties:try_get("nonwastedSurges", 0) + addSurges
            end
        end

        local potencymod = tonumber(self:try_get("potencymod", "none"))
        if self:try_get("potencymod") == "custom" then
            local customPotency = ExecuteGoblinScript(self:try_get("customPotency", "0"), lookupFunction, 0, "Custom Potency Modifier")
            if customPotency ~= nil then
                potencymod = tonumber(customPotency)
            end
        end
    
        if potencymod ~= nil then
            local pattern = "^(?<prefix>.*?<\\s*)(?<potency>[0-9]+)(?<postfix>.*)$"
            for i,tier in ipairs(rollProperties.tiers) do
                local output = ""
                local match = regex.MatchGroups(tier, pattern)
                while match ~= nil do

                    output = output .. match.prefix

                    local potency = tonumber(match.potency)
                    potency = potency + potencymod
                    output = output .. tostring(potency)

                    tier = match.postfix
                    match = regex.MatchGroups(tier, pattern)
                end

                output = output .. tier

                rollProperties.tiers[i] = output
            end
        end

        if self.modtype == "suppresseffects" then
            for i,tier in ipairs(rollProperties.tiers) do
                local m = regex.MatchGroups(tier, "^(?<prefix>.*?)(?<damage>\\d+\\s+[^0-9]*damage)(?<suffix>.*)$")
                if m ~= nil then
                    tier = m.damage
                else
                    tier = "No effect"
                end

                rollProperties.tiers[i] = tier
            end

            --this makes it so the cast won't record the tier, so tier-dependent effects won't be triggered.
            rollProperties.tierSuppressed = true
        end

        if self:has_key("addText") and trim(self.addText) ~= "" then
            local tieredText = BreakTextIntoTiers(StringInterpolateGoblinScript(self.addText, lookupFunction))
            for i,tier in ipairs(rollProperties.tiers) do
                rollProperties.tiers[i] = AppendTieredText(tier, tieredText[i])
            end
        end

        if self:has_key("replacePattern") and trim(self.replacePattern) ~= "" and
           self:has_key("replaceText") and trim(self.replaceText) ~= "" then
            local tieredText = BreakTextIntoTiers(StringInterpolateGoblinScript(self.replaceText, lookupFunction))
            for i,tier in ipairs(rollProperties.tiers) do
                rollProperties.tiers[i] = string.replace_insensitive(rollProperties.tiers[i], self.replacePattern, tieredText[i])
            end
        end
    end,

    modifyPowerRollCasting = function(self, creature, ability, options)
        if self:try_get("overrideCost", false) then
            local tempCopy = DeepCopy(ability)
            tempCopy.resourceNumber = ExecuteGoblinScript(self:try_get("resourceCostAmount", "1"), creature:LookupSymbol(options.symbols), 0, "Override Resource Cost")
            local tok = dmhub.LookupToken(creature)
            local costInfo = tempCopy:GetCost(tok)
            
            options.costOverride = costInfo

            return options
        end
    end,

    applyToRollLateness = function(self)
        local modType = ActivatedAbilityPowerRollBehavior.s_modificationTypesById[self.modtype]
        if modType ~= nil then
            return modType.lateness or 0
        end
    end,

    createEditor = function(modifier, element, options)
        options = options or {}

        local Refresh
        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            end

            local conditionType = "condition"
            if modifier.activationCondition == false then
                conditionType = "never"
            elseif modifier.activationCondition == true then
                conditionType = "always"
            end

            local children = {}

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formInput"},
                    text = modifier.name or "",
                    change = function(input)
                        modifier.name = input.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Description:",
                },
                gui.Input{
                    classes = {"formInput"},
                    width = 400,
                    multiline = true,
                    height = "auto",
                    maxHeight = 100,
                    minHeight = 16,
                    text = modifier.description or "",
                    characterLimit = 300,
                    change = function(input)
                        modifier.description = input.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Apply To:",
                },

                gui.Dropdown{
					height = 30,
					width = 260,
                    valign = "center",
					fontSize = 16,
                    options = g_powerRollTypes,
                    idChosen = modifier.rollType,
                    change = function(element)
                        modifier.rollType = element.idChosen
                        Refresh()
                    end,
                }
            }

            if modifier.rollType == "test_power_roll" or modifier.rollType == "opposed_power_roll" or modifier.rollType == "resistance_power_roll" then
                local options = DeepCopy(creature.attributeDropdownOptions)
                options[#options+1] = {
                    id = "all",
                    text = "All",
                }
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Characteristic:",
                    },

                    gui.Dropdown{
                        height = 30,
                        width = 260,
                        valign = "center",
                        fontSize = 16,
                        options = options,
                        idChosen = modifier:try_get("attribute", "all"),
                        change = function(element)
                            modifier.attribute = element.idChosen
                            Refresh()
                        end,
                    }
                }
            end

            if modifier.rollType == "test_power_roll" or modifier.rollType == "opposed_power_roll" then
                local skills = modifier:try_get("skills", {})
                for i,skillid in ipairs(skills) do
                    local skill = Skill.SkillsById[skillid]
                    if skill ~= nil then
                        children[#children+1] = gui.Label{
                            text = skill.name,
                            fontSize = 18,
                            height = 30,
                            width = 160,
                            halign = "left",
                            gui.DeleteItemButton{
                                halign = "right",
                                valign = "center",
                                height = 12,
                                width = 12,
                                click = function()
                                    table.remove(skills, i)
                                    Refresh()
                                end,
                            },
                        }
                    end
                end

                children[#children+1] = gui.Dropdown{
                    height = 30,
                    width = 260,
                    fontSize = 16,
                    valign = "center",
                    hasSearch = true,
                    textDefault = "Add Skill...",
                    options = Skill.skillsDropdownOptions,
                    change = function(element)
                        skills[#skills+1] = element.idChosen
                        modifier.skills = skills
                        Refresh()
                    end,
                }
            end

            children[#children+1] = modifier:UsageLimitEditor{}

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    text = "Resource Cost:",
                    classes = {"formLabel"},
                },

				gui.Dropdown{
					height = 30,
					width = 260,
					fontSize = 16,
                    valign = "center",
					idChosen = modifier:try_get("resourceCostType", "none"),
					options = {
						{
							id = "none",
							text = "None",
						},
						{
							id = "cost",
							text = "Malice/Heroic Resources",
						},
						{
							id = "multicost",
							text = "Malice/Heroic Resources+",
						},
                        {
                            id = "surges",
                            text = "Surges",
                        },
					},
					change = function(element)
                        modifier.resourceCostType = element.idChosen
                        Refresh()
					end,
				}
            }

            if modifier:try_get("resourceCostType", "none") ~= "none" then
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        text = "Cost:",
                        classes = {"formLabel"},
                    },
                    gui.GoblinScriptInput{
                        value = modifier:try_get("resourceCostAmount", "1"),
                        change = function(element)
                            modifier.resourceCostAmount = element.value
                            Refresh()
                        end,

                        documentation = {
                            domains = modifier:Domains(),
                            help = string.format("This GoblinScript is used to determine the cost of using the modifier."),
                            output = "number",
                            examples = {
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature affected by this modifier",
                            symbols = modifier:HelpAdditionalSymbols(g_powerRollSymbols),
                        },
                    },
                }

                children[#children+1] = gui.Check{
                    style = {
                        height = 30,
                        width = 160,
                        fontSize = 18,
                        halign = "left",
                    },

                    text = "Override Cost",
                    value = modifier:try_get("overrideCost", false),
                    change = function(element)
                        modifier.overrideCost = element.value
                        Refresh()
                    end,
                }   
                
            end


            if modifier.rollType == "ability_power_roll" or modifier.rollType == "enemy_ability_power_roll" then

                local keywords = modifier:try_get("keywords", {})
                children[#children+1] = gui.KeywordSelector{
                    keywords = keywords,
                    change = function()
                        modifier.keywords = keywords
                        Refresh()
                    end,
                }

                if table.count_elements(keywords) >= 2 then
                    children[#children+1] = gui.Check{
                        style = {
                            height = 30,
                            width = 220,
                            fontSize = 18,
                            halign = "left",
                        },

                        text = "Match Any Keywords",
                        value = modifier:try_get("matchAnyKeywords", false),
                        change = function(element)
                            modifier.matchAnyKeywords = element.value
                            Refresh()
                        end,
                    }
                end
            end

			children[#children+1] = modifier:FilterConditionEditor()

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    text = "Roll Requirement:",
                    classes = {"formLabel"},
                },

				gui.Dropdown{
					height = 30,
					width = 260,
					fontSize = 16,
                    valign = "center",
					idChosen = modifier:try_get("rollRequirement", "none"),
					options = {
						{
							id = "none",
							text = "None",
						},
						{
							id = "bane",
							text = "Bane on the Roll",
						},
						{
							id = "doublebane",
							text = "Double Bane on the Roll",
						},
						{
							id = "edge",
							text = "Edge on the Roll",
						},
						{
							id = "doubleedge",
							text = "Double Edge on the Roll",
						},
                        {
                            id ="nobane",
                            text = "No Bane or Double Bane on the Roll",
                        },
                        {
                            id ="noedge",
                            text = "No Edge or Double Edge on the Roll",
                        },
                        {
                            id ="skilled",
                            text = "Skilled",
                        },
                        {
                            id ="unskilled",
                            text = "Not Skilled",
                        },
                        {
                            id = "surges",
                            text = "Has Surges",
                        },
					},
					change = function(element)
                        modifier.rollRequirement = element.idChosen
                        Refresh()
					end,
				}
            }

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					text = "Activation:",
					classes = {"formLabel"},
				},

				gui.Dropdown{
					height = 30,
					width = 260,
					fontSize = 16,
                    valign = "center",
					idChosen = conditionType,
					options = {
						{
							id = "never",
							text = "Never",
						},
						{
							id = "always",
							text = "Always",
						},
						{
							id = "condition",
							text = "Condition",
						},
					},
					change = function(element)
						if element.idChosen ~= conditionType then
							if element.idChosen == "never" then
								modifier.activationCondition = false
							elseif element.idChosen == "always" then
								modifier.activationCondition = true
							else
								modifier.activationCondition = ""
							end
							Refresh()
						end
					end,
				}

			}

            if modifier.activationCondition ~= true and modifier.activationCondition ~= false then
                local helpSymbols = CharacterModifier.defaultHelpSymbols
                if modifier.rollType == "ability_power_roll" or modifier.rollType == "enemy_ability_power_roll" then
                    helpSymbols = g_powerRollSymbols
                end

                helpSymbols = DeepCopy(helpSymbols)
                helpSymbols.title = {
                    name = "Title",
                    type = "text",
                    desc = "The title of the roll",
                    examples = "Recall Lore Test to Recall Location of Amulet",
                }

                children[#children+1] = gui.GoblinScriptInput{
					placeholderText = "Enter display criteria...",
					value = modifier.displayCondition,
					change = function(element)
						modifier.displayCondition = element.value
						Refresh()
					end,

					documentation = {
						domains = modifier:Domains(),
						help = string.format("This GoblinScript is used to determine whether or not this modifier will be displayed as an option for a specific roll."),
						output = "boolean",
						examples = {
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature affected by this modifier",
						symbols = modifier:HelpAdditionalSymbols(helpSymbols),
					},
				}


                children[#children+1] = gui.GoblinScriptInput{
					placeholderText = "Enter activation criteria...",
					value = modifier.activationCondition,
					change = function(element)
						modifier.activationCondition = element.value
						Refresh()
					end,

					documentation = {
						domains = modifier:Domains(),
						help = string.format("This GoblinScript is used to determine whether or not this modifier will be applied to a given roll. It determines the default value for the checkbox that appears next to it when the roll occurs. The player can always override the value manually."),
						output = "boolean",
						examples = {
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature affected by this modifier",
						symbols = modifier:HelpAdditionalSymbols(helpSymbols),
					},
				}
            end


            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Roll Mod:",
                },

                gui.Dropdown{
                    options = ActivatedAbilityPowerRollBehavior.s_modificationTypes,
                    valign = "center",
                    idChosen = modifier.modtype,
                    change = function(element)
                        modifier.modtype = element.idChosen
                        Refresh()
                    end,
                }
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.modtype ~= "replaceroll" and modifier.modtype ~= "appendroll", 'collapsed-anim')},
                gui.Label{
                    classes = {"formLabel"},
                    text = cond(modifier.modtype == "replaceroll", "Replace roll with:", "Append to roll:"),
                },
                gui.Input{
                    classes = {"formInput"},
                    width = 260,
                    halign = "left",
                    text = modifier:try_get("replaceText", ""),
                    change = function(element)
                        modifier.replaceText = element.text
                    end,
                }
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Modify Potency:",
                },

                gui.Dropdown{
                    options = {
                        {
                            id = "none",
                            text = "None",
                        },
                        {
                            id = "1",
                            text = "+1",
                        },
                        {
                            id = "2",
                            text = "+2",
                        },
                        {
                            id = "-1",
                            text = "-1",
                        },
                        {
                            id = "-2",
                            text = "-2",
                        },
                        {
                            id = "custom",
                            text = "Custom",
                        },
                    },
                    valign = "center",
                    idChosen = modifier:try_get("potencymod", "none"),
                    change = function(element)
                        modifier.potencymod = element.idChosen
                        Refresh()
                    end,
                }
            }

            if modifier:try_get("potencymod") == "custom" then
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Custom Potency:",
                    },

                    gui.GoblinScriptInput{
                        value = modifier:try_get("customPotency", ""),
                        change = function(element)
                            modifier.customPotency = element.value
                            Refresh()
                        end,

                        documentation = {
                            domains = modifier:Domains(),
                            help = string.format("This GoblinScript is used to determine the custom potency value for the roll."),
                            output = "number",
                            examples = {
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature affected by this modifier",
                            symbols = modifier:HelpAdditionalSymbols(g_powerRollSymbols),
                        },
                    }
                }
            end

            if options.triggered then
                children[#children+1] = gui.Check{
                    style = {
                        height = 30,
                        width = 160,
                        fontSize = 18,
                        halign = "left",
                    },

                    text = "Change Target",
                    value = modifier:try_get("changeTarget", false),
                    change = function(element)
                        modifier.changeTarget = element.value
                        Refresh()
                    end,
                }

                if modifier:try_get("changeTarget", false) then

                    local helpSymbols = DeepCopy(CharacterModifier.defaultHelpSymbols)

                    helpSymbols.current = {
                        name = "Current",
                        type = "creature",
                        desc = "The current target of the power roll.",
                    }

                    helpSymbols.target = {
                        name = "Target",
                        type = "creature",
                        desc = "The potential new target of the power roll.",
                    }

                    helpSymbols.triggerer = {
                        name = "Triggerer",
                        type = "creature",
                        desc = "The creature that is triggering this modification.",
                    }

                    helpSymbols.caster = {
                        name = "Caster",
                        type = "creature",
                        desc = "The caster of the power roll.",
                    }

                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Retarget Range:",
                        },
                        gui.Dropdown{
                            idChosen = modifier:try_get("changeTargetRange", "none"),
                            options = {
                                {
                                    id = "none",
                                    text = "Same as Trigger",
                                },
                                {
                                    id = "ability",
                                    text = "Same as Triggering Ability",
                                },
                                {
                                    id = "distance",
                                    text = "Distance from Triggerer",
                                },
                            },

                            change = function(element)
                                modifier.changeTargetRange = element.idChosen
                                Refresh()
                            end,
                        }
                    }

                    if modifier:try_get("changeTargetRange", "none") == "distance" then
                        children[#children+1] = gui.Panel{
                            classes = {"formPanel"},
                            gui.Label{
                                classes = {"formLabel"},
                                text = "Retarget Distance:",
                            },
                            gui.Input{
                                classes = {"formInput"},
                                width = 40,
                                halign = "left",
                                characterLimit = 3,
                                text = modifier:try_get("changeTargetDistance", 0),
                                change = function(element)
                                    if tonumber(element.text) ~= nil then
                                        modifier.changeTargetDistance = tonumber(element.text)
                                    else 
                                        element.text = modifier:try_get("changeTargetDistance", 0)
                                    end
                                    Refresh()
                                end,
                            }
                        }
                    end

                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Retarget Filter:",
                        },
                        gui.GoblinScriptInput{
                            value = modifier:try_get("changeTargetFilter", ""),
                            change = function(element)
                                modifier.changeTargetFilter = element.value
                                Refresh()
                            end,

                            documentation = {
                                domains = modifier:Domains(),
                                help = string.format("This GoblinScript is used to determine the target of the power roll."),
                                output = "creature",
                                examples = {
                                },
                                subject = creature.helpSymbols,
                                subjectDescription = "The creature that is triggering this modification. Only available if this modifier is triggered.",
                                symbols = helpSymbols,
                            },
                        }
                    }

                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Retarget Effect:",
                        },

                        gui.Dropdown{
                            options = {
                                {
                                    id = "all",
                                    text = "All Effects",
                                },
                                {
                                    id = "forcemove",
                                    text = "Forced Movement",
                                },
                                {
                                    id = "none",
                                    text = "No Effects",
                                },
                            },
                            valign = "center",
                            idChosen = modifier:try_get("changeTargetEffect", "all"),
                            change = function(element)
                                modifier.changeTargetEffect = element.idChosen
                                Refresh()
                            end,
                        }
                    }
                end
            end

            local helpSymbols = DeepCopy(CharacterModifier.defaultHelpSymbols)
            helpSymbols.target = {
                name = "Target",
                type = "creature",
                desc = "The target of the power roll.",
            }

            helpSymbols.triggerer = {
                name = "Triggerer",
                type = "creature",
                desc = "The creature that is triggering this modification. Only available if this modifier is triggered.",
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Damage:",
                },

                gui.GoblinScriptInput{
					placeholderText = "Enter damage...",
					value = modifier:try_get("damageModifier", ""),
					change = function(element)
						modifier.damageModifier = element.value
                        Refresh()
					end,

					documentation = {
						domains = modifier:Domains(),
						help = string.format("This GoblinScript is used to determine the amount of damage that will be added to the roll."),
						output = "number",
						examples = {
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature that is attacking",
						symbols = helpSymbols,
					},
				},
            }

            if modifier:try_get("damageModifier", "") ~= "" and not (modifier.rollType == "project_roll") then

                local damageTypeOptions = {}
                damageTypeOptions[#damageTypeOptions+1] = {
                    id = "none",
                    text = "Add to Existing Damage",
                }
                for _,damageType in ipairs(rules.damageTypesAvailable) do
                    damageTypeOptions[#damageTypeOptions+1] = {
                        id = damageType,
                        text = damageType,
                    }
                end

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Damage Type:",
                    },
                    gui.Dropdown{
                        idChosen = modifier:try_get("damageModifierType", "none"),
                        options = damageTypeOptions,
                        change = function(element)
                            modifier.damageModifierType = element.idChosen
                            Refresh()
                        end,
                    }
                }
            end

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Damage Multiplier:",
                },
                gui.Dropdown{
                    options = {
                        {
                            id = "full",
                            text = "Full Damage",
                        },
                        {
                            id = "half",
                            text = "Half Damage",
                        },
                    },
                    idChosen = modifier:try_get("damageMultiplier", "full"),
                    change = function(element)
                        modifier.damageMultiplier = element.idChosen
                    end,
                }
            }

            local damageTypeOptions = {}
            damageTypeOptions[#damageTypeOptions+1] = {
                id = "none",
                text = "Choose...",
            }
            for _,damageType in ipairs(rules.damageTypesAvailable) do
                damageTypeOptions[#damageTypeOptions+1] = {
                    id = damageType,
                    text = damageType,
                }
            end

            local AddDamageType
            local dropdownDestType = gui.Dropdown{
                idChosen = "none",
                fontSize = 12,
                width = 120,
                height = 16,
                options = damageTypeOptions,
                change = function(element)
                    AddDamageType()
                end,
            }

            damageTypeOptions[#damageTypeOptions+1] = {id = "all", text = "All"}

            local dropdownSourceType = gui.Dropdown{
                idChosen = "none",
                fontSize = 12,
                width = 120,
                height = 16,
                options = damageTypeOptions,
                change = function(element)
                    AddDamageType()
                end,
            }

            AddDamageType = function()
                if dropdownDestType.idChosen == "none" or dropdownSourceType.idChosen == "none" then
                    return
                end

                local mappings = modifier:get_or_add("damageTypeMappings", {})
                mappings[dropdownSourceType.idChosen] = dropdownDestType.idChosen
                Refresh()
            end

            local damageTypeChildren = {}

            for k,v in sorted_pairs(modifier:try_get("damageTypeMappings", {})) do
                damageTypeChildren[#damageTypeChildren+1] = gui.Label{
                    text = string.format("%s -> %s", k, v),
                    width = "auto",
                    height = "auto",
                    fontSize = 14,
                    gui.DeleteItemButton{
                        x = 12,
                        width = 8,
                        height = 8,
                        halign = "right",
                        valign = "center",
                        press = function()
                            modifier.damageTypeMappings[k] = nil
                            Refresh()
                        end,
                    },
                }
            end

            local hasAll = modifier:try_get("damageTypeMappings", {})["all"] ~= nil
            damageTypeChildren[#damageTypeChildren+1] = gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                classes = {cond(hasAll, "collapsed"), cond(modifier.rollType == "project_roll", "collapsed-anim")},

                dropdownSourceType,
                gui.Label{
                    fontSize = 14,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    text = "->",
                    hmargin = 4,
                },
                dropdownDestType,
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Damage Type:",
                },
                gui.Panel{
                    width = 300,
                    height = "auto",
                    flow = "vertical",
                    children = damageTypeChildren,
                }
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Surges:",
                },

                gui.GoblinScriptInput{
					placeholderText = "Enter surges...",
					value = modifier:try_get("surges", ""),
					change = function(element)
						modifier.surges = element.value
                        Refresh()
					end,

					documentation = {
						domains = modifier:Domains(),
						help = string.format("This GoblinScript is used to determine the amount of surges that will be added to the roll."),
						output = "number",
						examples = {
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature that is attacking",
						symbols = helpSymbols,
					},
				},
            }

            if modifier:try_get("surges", "") ~= "" then
                children[#children+1] = gui.Check{
                    text = "Surges can be Kept",
                    value = modifier:try_get("surgesCanBeKept", false),
                    change = function(element)
                        modifier.surgesCanBeKept = element.value
                        Refresh()
                    end,
                }
            end

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier:try_get("rollRequirement") ~= "surges", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Change Surge Damage to:",
                },
                gui.Dropdown{
                    idChosen = modifier:try_get("surgeDamageType", "none"),
                    options = rules.damageTypesAvailable,
                    change = function(element)
                        modifier.surgeDamageType = element.idChosen
                        Refresh()
                    end,
                },
            }

            local adjustmentsSymbols = modifier:HelpAdditionalSymbols(helpSymbols)
            adjustmentsSymbols.charges = {
                name = "Charges",
                type = "number",
                desc = "The number of applications of this adjustment being applied.",
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Adjustments:",
                },

                gui.Panel{
                    classes = {"formLabel"},
                    flow = "vertical",
                    create = function(element)
                        local children = {}
                        local adjustments = modifier:try_get("adjustments", {})
                        for i,adjustment in ipairs(adjustments) do
                            local panel = gui.Panel{
                                flow = "horizontal",
                                width = "100%",
                                height = 30,
                                gui.Dropdown{
                                    width = 120,
                                    halign = "left",
                                    options = {
                                        {
                                            id = "push",
                                            text = "push",
                                        },
                                        {
                                            id = "pull",
                                            text = "pull",
                                        },
                                        {
                                            id = "slide",
                                            text = "slide",
                                        },
                                        {
                                            id = "jump",
                                            text = "jump",
                                        },
                                    },
                                    idChosen = adjustment.type,
                                    change = function(element)
                                        adjustments[i].type = element.idChosen
                                        Refresh()
                                    end,
                                },

                                gui.GoblinScriptInput{
                                    placeholderText = "Enter adjustment...",
                                    value = adjustment.value,
                                    width = 180,
                                    change = function(element)
                                        adjustment.value = element.value
                                        Refresh()
                                    end,

                                    documentation = {
                                        domains = modifier:Domains(),
                                        help = string.format("This GoblinScript is used to determine the adjustment made to the power table value."),
                                        output = "number",
                                        examples = {
                                        },
                                        subject = creature.helpSymbols,
                                        subjectDescription = "The creature affected by this modifier",
                                        symbols = adjustmentsSymbols,
                                    },
                                },

                                gui.DeleteItemButton{
                                    halign = "right",
                                    width = 12,
                                    height = 12,
                                    click = function()
                                        table.remove(adjustments, i)
                                        Refresh()
                                    end,
                                }
                            }

                            children[#children+1] = panel
                        end

                        children[#children+1] = gui.AddButton{
                            width = 16,
                            height = 16,
                            halign = "left",
                            click = function(element)
                                adjustments[#adjustments+1] = {
                                    type = "push",
                                    value = 1,
                                }
                                modifier.adjustments = adjustments
                                Refresh()
                            end,
                        }

                        element.children = children
                    end,
                },
            }


            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Add to Table:",
                    hover = function(element)
                        gui.Tooltip("This will add the text to the end of all tiers of the power roll. You can use something like Shift 2/3/4 to apply different amounts to each tier.")(element)
                    end,
                },

                gui.Input{
                    classes = {"formInput"},
                    width = 260,
                    text = modifier:try_get("addText", ""),
                    change = function(element)
                        modifier.addText = element.text
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Replace in Table:",
                    hover = function(element)
                        gui.Tooltip("This will replace text in the power table with new text.")(element)
                    end,
                },

                gui.Input{
                    classes = {"formInput"},
                    width = 114,
                    placeholderText = "Replace...",
                    text = modifier:try_get("replacePattern", ""),
                    change = function(element)
                        modifier.replacePattern = element.text
                        Refresh()
                    end,
                },

                gui.Input{
                    classes = {"formInput"},
                    width = 114,
                    lmargin = 12,
                    placeholderText = "New Text...",
                    text = modifier:try_get("replaceText", ""),
                    change = function(element)
                        modifier.replaceText = element.text
                        Refresh()
                    end,
                },

            }



            if options.triggered then
                children[#children+1] = gui.Check{
                    style = {
                        height = 30,
                        width = 160,
                        fontSize = 18,
                        halign = "left",
                    },

                    text = "Has Trigger Before Ability",
                    value = modifier:try_get("hasTriggerBefore", false),
                    change = function(element)
                        modifier.hasTriggerBefore = element.value
                        if element.value and modifier:has_key("triggerBefore") == false then
                            modifier.triggerBefore = TriggeredAbility.Create{
                                trigger = "d20roll",
                            }
                        end
                        Refresh()
                    end,
                }

                if modifier:try_get("hasTriggerBefore", false) then
                    children[#children+1] = gui.PrettyButton{
                        halign = "left",
                        width = 220,
                        height = 50,
                        fontSize = 24,
                        text = "Edit Trigger",
                        click = function(element)
                            local fn = function(element, modifier, savefn)
                                if modifier:has_key("triggerBefore") then
                                    element.root:AddChild(modifier.triggerBefore:ShowEditActivatedAbilityDialog{
                                        title = "Edit Trigger",
                                        hide = {"appearance", "abilityInfo"},
                                        destroy = savefn,
                                    })
                                end    
                            end
            
                            element.root:FireEventTree("editCompendiumFeature", modifier, fn)
            
                            fn(element, modifier)
                        end,
                    }

                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Activation Criteria:",
                            hover = gui.Tooltip("After the Trigger has run this formula will be used to determine whether the modification will apply."),
                        },
                        gui.GoblinScriptInput{
                            value = modifier:try_get("triggerBeforeCondition", ""),
                            change = function(element)
                                modifier.triggerBeforeCondition = element.value
                                Refresh()
                            end,

                            documentation = {
                                domains = modifier:Domains(),
                                help = string.format("This GoblinScript is used to determine whether or not this modifier will be applied to a given roll. It determines the default value for the checkbox that appears next to it when the roll occurs. The player can always override the value manually."),
                                output = "boolean",
                                examples = {
                                },
                                subject = creature.helpSymbols,
                                subjectDescription = "The creature affected by this modifier",
                                symbols = modifier:HelpAdditionalSymbols(helpSymbols),
                            },
                        }
                    }
                end
            end

            children[#children+1] = gui.Check{

				style = {
					height = 30,
					width = 160,
					fontSize = 18,
					halign = "left",
				},

				text = "Has Custom Trigger",
				value = modifier:try_get("hasCustomTrigger", false),
				change = function(element)
					modifier.hasCustomTrigger = element.value
					if element.value and modifier:has_key("customTrigger") == false then
						modifier.customTrigger = TriggeredAbility.Create{
							trigger = "d20roll",
						}
					end
					Refresh()
				end,
			}

			if modifier:try_get("hasCustomTrigger", false) then
				children[#children+1] = gui.PrettyButton{
					halign = "left",
					width = 220,
					height = 50,
					fontSize = 24,
					text = "Edit Trigger",
					click = function(element)
                        local fn = function(element, modifier, savefn)
                            if modifier:has_key("customTrigger") then
                                element.root:AddChild(modifier.customTrigger:ShowEditActivatedAbilityDialog{
                                    title = "Edit Trigger",
                                    hide = {"appearance", "abilityInfo"},
                                    destroy = savefn,
                                })
                            end    
                        end
        
                        element.root:FireEventTree("editCompendiumFeature", modifier, fn)
        
                        fn(element, modifier)
					end,
				}
			end

            element.children = children
        end

        Refresh()
    end,
}

function CharacterModifier:DescribeModifyPowerRoll(modContext, creature, rollType, options)
    if self:ShouldShowInPowerRollDialog(modContext, creature, rollType, options) then
        return {
            modifier = self,
            context = modContext,
        }
    end

    return nil
end

function CharacterModifier:ShouldShowInPowerRollDialog(modContext, creature, rollType, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    local shouldShow = typeInfo.shouldShowInPowerRollDialog
    if shouldShow ~= nil then
        self:InstallSymbolsFromContext(modContext)
        self:InstallSymbolsFromContext(options)
        local result = shouldShow(self, creature, rollType, nil, options)
        return result
    end

    return false
end

function CharacterModifier:HintModifyPowerRolls(modContext, creature, rollType, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    local hint = typeInfo.hintPowerRoll
    if hint ~= nil then
        local result = hint(self, creature, rollType, options)
        return result
    end

    return nil
end

function CharacterModifier:ModifyPowerRolls(modContext, creature, rollType, roll, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    local modifyPowerRoll = typeInfo.modifyPowerRoll
    if modifyPowerRoll ~= nil then
        self:InstallSymbolsFromContext(modContext)
        self:InstallSymbolsFromContext(options)
        return modifyPowerRoll(self, creature, rollType, roll, options)
    end

    return roll
end

function CharacterModifier:ModifyPowerRollCasting(modContext, creature, ability, options)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    local modifyPowerRollCasting = typeInfo.modifyPowerRollCasting
    if modifyPowerRollCasting ~= nil then
        self:InstallSymbolsFromContext(modContext)
        self:InstallSymbolsFromContext(options)
        return modifyPowerRollCasting(self, creature, ability, options)
    end

    return nil
end

function CharacterModifier:ApplyToRoll(context, casterCreature, targetCreature, rollType, roll)
    local result = self:ModifyPowerRolls(context, casterCreature, rollType, roll, {})
    return result
end

function CharacterModifier:ApplyToRollLateness()
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.applyToRollLateness ~= nil then
        return typeInfo.applyToRollLateness(self)
    end

    return 0
end

function CharacterModifier:HasRenderOnRoll()
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.renderOnRoll ~= nil then
        return true
    end

    return false
end

function CharacterModifier:RenderOnRoll(rollInfo, triggerInfo, targetPanel)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.renderOnRoll ~= nil then
        typeInfo.renderOnRoll(self, rollInfo, triggerInfo, targetPanel)
    end
end

--returns "buff", "debuff", or nil
function CharacterModifier:BuffOrDebuff(context)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.buffOrDebuff ~= nil then
        return typeInfo.buffOrDebuff(self, context)
    end
end