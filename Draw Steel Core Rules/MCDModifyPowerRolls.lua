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

--Resolves the value of the characteristic used for a power roll, or nil when
--the roll uses no characteristic (so callers leave the GoblinScript symbol
--absent). Tests and resistance rolls carry the characteristic id directly in
--options.attribute; ability rolls keep their characteristic in the roll formula
--(e.g. "2d10 + Reason"), resolved via the ability itself.
local function ResolveRollCharacteristic(creature, options)
    local attrid = options.attribute
    if attrid ~= nil and attrid ~= "none" then
        return creature:AttributeMod(attrid)
    end
    if options.ability ~= nil and options.ability.GetRollCharacteristicValue ~= nil then
        return options.ability:GetRollCharacteristicValue(creature)
    end
    return nil
end

--A damageTypeMappings value may be a plain string (legacy: one destination
--type) or a list of strings (the user picks one at roll time). Returns the
--value normalized to a list of destination damage types.
--- @param value string|string[]
--- @return string[]
function CharacterModifier.DamageMappingDestinations(value)
    if type(value) == "table" then
        return value
    end
    return {value}
end

--Resolves which destination damage type a mapping should convert to, taking
--into account any roll-time choice stored on this modifier instance (set by
--the roll dialog's badge dropdown). Falls back to the first destination.
--- @param source string
--- @param value string|string[]
--- @return string
function CharacterModifier:ResolveDamageMappingDestination(source, value)
    local dests = CharacterModifier.DamageMappingDestinations(value)
    if #dests <= 1 then
        return dests[1]
    end

    local choices = self:try_get("_tmp_damageTypeChoices")
    if choices ~= nil then
        for _,d in ipairs(dests) do
            if d == choices[source] then
                return d
            end
        end
    end

    return dests[1]
end

local function RollTypeMatches(modifier, rollType, options)
    if modifier.rollType == "all" and rollType ~= "enemy_ability_power_roll" then
        return true
    end

    if rollType ~= modifier.rollType then
        return false
    end

    --Only apply "Enemy Ability Rolls vs Us" to harmful abilities:
    --the caster must not be a friend of the target.
    if rollType == "enemy_ability_power_roll" and options ~= nil and options.caster ~= nil and options.target ~= nil then
        local casterToken = dmhub.LookupToken(options.caster)
        local targetToken = dmhub.LookupToken(options.target)
        if casterToken ~= nil and targetToken ~= nil and casterToken:IsFriend(targetToken) then
            return false
        end
    end

    return true
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
            --Deferred until the casts currently resolving on this client
            --complete (see ActivatedAbility.RunWhenCastsComplete): a custom
            --trigger activated from the roll dialog (e.g. In All This
            --Confusion's teleport) resolves after the triggering ability
            --finishes (damage, forced movement), not mid-cast. Deferring here,
            --at the source, also covers the locally-controlled-target case,
            --where the invoke behavior runs ExecuteInvoke directly instead of
            --going through the (already deferred) remoteInvokes queue. It also
            --lifts the trigger's cast out of the ModifyProperties execute
            --block this runs inside (see ConsumeResource in DSRollDialog).
            ActivatedAbility.RunWhenCastsComplete(function()
                if token == nil or not token.valid then
                    return
                end
                modifier.customTrigger:Trigger(modifier, creature, modifier:AppendSymbols{}, nil, modContext)
            end)
		end

		--Arm-on-toggle (Elemental Avatar / Dragonseal): when a power modifier
		--carrying an armEffect is applied (its roll-dialog checkbox is checked),
		--apply that marker ongoing effect to the caster synchronously HERE, at
		--roll-confirm -- before the strike's damage lands. A dealdamage trigger
		--can then read the flag the marker grants and deliver on this same
		--strike. (The customTrigger above is deferred until after the cast, so
		--it is too late to gate same-strike delivery.)
		local armEffect = modifier:try_get("armEffect")
		if armEffect ~= nil then
			local armToken = dmhub.LookupToken(creature)
			if armToken ~= nil and armToken.valid then
				armToken.properties:ApplyOngoingEffect(armEffect, 0, nil, {})
			end
		end

        if modifier:has_key("baseModifier") and (modifier:try_get("gobefore", false)) and (not modifier:try_get("overridebase", false)) then
            print("TRIGGER:: BASE GOES LAST")
            CharacterModifier.TypeInfo.power.triggerOnUse(modifier.baseModifier, creature, modContext)
        end
	end,

    hintPowerRoll = function(self, creature, rollType, options)
        options = options or {}

        if type(self:try_get("activationAfterRoll", false)) == "string" then
            return {
                result = false,
                justification = {}
            }
        end

        if self:has_key("baseModifier") and (not self:try_get("overrideBase", false)) then
            local baseResult = CharacterModifier.TypeInfo.power.hintPowerRoll(self.baseModifier, creature, rollType, options)
            if baseResult.result == false then
                return baseResult
            end
        end


        if (self.activationCondition == false) or (not RollTypeMatches(self, rollType, options)) then
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
                    keywordFail[#keywordFail+1] = ActivatedAbility.CanonicalKeyword(keyword)
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

		local powerRollSymbols = self:AppendSymbols{
			ability = GenerateSymbols(options.ability),
			target = GenerateSymbols(options.target),
            title = options.title or "",
		}

		--Expose the value of the characteristic used for this roll (e.g. 2 for a
		--Might +2 roll, -1 for an Agility -1 roll). Left absent when the roll uses
		--no characteristic so a condition can tell "no characteristic" apart from
		--"characteristic of 0".
		local rollCharacteristic = ResolveRollCharacteristic(creature, options)
		if rollCharacteristic ~= nil then
			powerRollSymbols.rollcharacteristic = rollCharacteristic
		end

		local lookupFunction = creature:LookupSymbol(powerRollSymbols)

        print("POWER ROLL:: OPTIONS:", options)

        return {
            result = GoblinScriptTrue(ExecuteGoblinScript(self.activationCondition, lookupFunction, 0, "Power Roll Activation Condition")),
            justification = {},
        }
    end,

    shouldShowInPowerRollDialog = function(self, creature, rollType, roll, options)

        if type(self:try_get("activationAfterRoll", false)) == "string" then
            return false
        end

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

        if not RollTypeMatches(self, rollType, options) then
            return false
        end

        if not self:PassesFilter(creature) then
            return false
        end

        if self.displayCondition ~= "" then
            local displaySymbols = self:AppendSymbols{
                ability = GenerateSymbols(options.ability),
                target = GenerateSymbols(options.target),
                caster = GenerateSymbols(options.caster),
                cast = options.symbols and GenerateSymbols(options.symbols.cast),
                title = options.title or "",
            }

            --See hintPowerRoll: expose the characteristic value used for this
            --roll, absent when the roll uses no characteristic.
            local rollCharacteristic = ResolveRollCharacteristic(creature, options)
            if rollCharacteristic ~= nil then
                displaySymbols.rollcharacteristic = rollCharacteristic
            end

            local lookupFunction = creature:LookupSymbol(displaySymbols)

            if not GoblinScriptTrue(ExecuteGoblinScript(self.displayCondition, lookupFunction, 0, "Power Roll Activation Condition")) then
                return false
            end
        end

        return true
    end,

    shouldShowInPowerRollDialogAfterRoll = function(self, creature, rollType, roll, options)
        if type(self:try_get("activationAfterRoll", false)) ~= "string" then
            return false
        end
        if not RollTypeMatches(self, rollType, options) then
            return false
        end
        if not self:PassesFilter(creature) then
            return false
        end
        return true
    end,

    hintPowerRollAfter = function(self, creature, rollType, options)
        options = options or {}

        if not RollTypeMatches(self, rollType, options) then
            return { result = false, justification = {} }
        end

        if self:HasResourcesAvailable(creature) == false then
            return {
                result = false,
                justification = {"You have expended all uses of this ability."},
            }
        end

        local lookupFunction = creature:LookupSymbol(self:AppendSymbols{
            ability = GenerateSymbols(options.ability),
            target  = GenerateSymbols(options.target),
            caster  = GenerateSymbols(options.caster),
            cast    = options.symbols and GenerateSymbols(options.symbols.cast),
            title   = options.title or "",
        })

        if self:try_get("displayAfterRoll", "") ~= "" then
            if not GoblinScriptTrue(ExecuteGoblinScript(self.displayAfterRoll, lookupFunction, 0, "Power Roll After Display Condition")) then
                return nil
            end
        end

        if self.activationAfterRoll == "" then
            return { result = false, justification = {} }
        end

        return {
            result = GoblinScriptTrue(ExecuteGoblinScript(self.activationAfterRoll, lookupFunction, 0, "Power Roll After Activation Condition")),
            justification = {},
        }
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
        if modType == nil then
            return roll
        end
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
            --Resolve each mapping value (possibly a list of candidate
            --destinations) down to the single chosen destination type.
            if damageTypeMappings["all"] ~= nil then
                local mapto = self:ResolveDamageMappingDestination("all", damageTypeMappings["all"])
                damageTypeMappings = {}
                for _,damageType in ipairs(rules.damageTypesAvailable) do
                    damageTypeMappings[damageType] = mapto
                end
            else
                local resolved = {}
                for k,v in pairs(damageTypeMappings) do
                    resolved[k] = self:ResolveDamageMappingDestination(k, v)
                end
                damageTypeMappings = resolved
            end
            for i=1,#rollProperties.tiers do
                local tier = rollProperties.tiers[i]
                for k,v in pairs(damageTypeMappings) do
                    if k == "untyped" then
                        --Untyped means untyped: only match a number followed directly by
                        --"damage" with no damage-type word in between. Typed damage is
                        --only converted when its own type key is in the mappings.
                        local m = regex.MatchGroups(tier, "^(?<prefix>.*?)(?<damage>\\d+)\\s+damage(?<suffix>.*)$")
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
                            tier = string.format("%s; %s", extraDamage, tier)
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

                    if damageMultiplier == "half" then
                        rollProperties.tiers[i] = string.format("%s (half)%s", before, after)
                    else
                        rollProperties.tiers[i] = string.format("%s (no damage)%s", before, after)
                    end
                end
            end
        end

        local damageReduction = self:try_get("damageReduction", "")
        if damageReduction ~= "" then
            local reduction = ExecuteGoblinScript(damageReduction, lookupFunction, 0, "Damage reduction")
            reduction = tonumber(reduction) or 0
            if reduction > 0 then
                for i,tier in ipairs(rollProperties.tiers) do
                    local match = regex.MatchGroups(tier, "(?<damage>\\d+)\\s+(\\+\\s*\\d+d\\d+\\s+)?([a-zA-Z]+\\s+)?damage", {indexes = true})
                    if match ~= nil then
                        local index = match.damage.index
                        local length = match.damage.length
                        local before = string.sub(tier, 1, index-1)
                        local after = string.sub(tier, index+length)
                        local damageValue = round(tonumber(match.damage.value))
                        damageValue = math.max(0, round(damageValue - reduction))
                        rollProperties.tiers[i] = string.format("%s%d%s", before, damageValue, after)
                    end
                end
            end
        end

        for i,adjustment in ipairs(self:try_get("adjustments", {})) do
            local typePattern = adjustment.type
            if typePattern == "any" then typePattern = "push|pull|slide" end
            local pattern = "^(?<prefix>.*)(?<type>" .. typePattern .. ")\\s+(?<value>\\d+)(?<postfix>.*)$"

            for j,tier in ipairs(rollProperties.tiers) do
                local match = regex.MatchGroups(tier, pattern)
                if match ~= nil then
                    local value = safe_toint(match.value)
                    local newValue
                    if adjustment.operation == "multiply" then
                        local adj = ExecuteGoblinScript(adjustment.value, lookupFunction, 1, "Determine adjustment")
                        newValue = math.max(0, math.floor(value * (adj or 1)))
                    else
                        local adj = ExecuteGoblinScript(adjustment.value, lookupFunction, 1, "Determine adjustment")
                        newValue = math.max(0, value + (adj or 0))
                    end
                    local prefix = match.prefix
                    local typeOutput = match.type
                    if self:try_get("vertical", false) and match.type ~= "jump" then
                        prefix = regex.ReplaceAll(prefix, "vertical\\s+$", "")
                        typeOutput = "vertical " .. match.type
                    end
                    rollProperties.tiers[j] = string.format("%s%s %d%s", prefix, typeOutput, newValue, match.postfix)
                end
            end
        end

        --replaceForcedMovement rewrites the forced-movement TYPE word in each tier
        --(e.g. "push 2" -> "slide 2"). The displayed power table updates live, and
        --because forced movement is resolved by parsing the tier text (see
        --TierSymbols in MCDMAbilityRollBehavior.lua), the actual resolved movement
        --changes type as well. Value/distance is left untouched -- use `adjustments`
        --to change distance. Shape: { from = "push", to = "slide" }. `from` may be
        --"any" to match push/pull/slide regardless of original type.
        local replaceForcedMovement = self:try_get("replaceForcedMovement")
        if replaceForcedMovement ~= nil and replaceForcedMovement.from ~= nil and replaceForcedMovement.to ~= nil then
            local fromPattern = replaceForcedMovement.from
            if fromPattern == "any" then
                fromPattern = "push|pull|slide"
            end
            local pattern = "^(?<prefix>.*?)(?<vert>vertical\\s+)?(?<type>" .. fromPattern .. ")(?<gap>\\s+\\d+)(?<postfix>.*)$"
            for j,tier in ipairs(rollProperties.tiers) do
                local output = ""
                local rest = tier
                local match = regex.MatchGroups(rest, pattern)
                while match ~= nil do
                    output = output .. match.prefix .. (match.vert or "") .. replaceForcedMovement.to .. match.gap
                    rest = match.postfix
                    match = regex.MatchGroups(rest, pattern)
                end
                rollProperties.tiers[j] = output .. rest
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
            local damageMultiplier = self:try_get("damageMultiplier", "full")
            for i,tier in ipairs(rollProperties.tiers) do
                local m = regex.MatchGroups(tier, "^(?<prefix>.*?)(?<damage>\\d+\\s+[^0-9]*damage)(?<suffix>.*)$")
                if m ~= nil then
                    tier = m.damage
                    if damageMultiplier == "half" then
                        tier = tier .. " (half)"
                    elseif damageMultiplier ~= "full" then
                        tier = tier .. " (no damage)"
                    end
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

            --Imported/YAML-authored modifiers may lack activationCondition
            --entirely (only the editor's init path sets it); treat missing
            --as false, matching the init default.
            local activationCondition = modifier:try_get("activationCondition", false)

            local conditionType = "condition"
            if activationCondition == false then
                if type(modifier:try_get("activationAfterRoll", false)) == "string" then
                    conditionType = "condition_after_roll"
                else
                    conditionType = "never"
                end
            elseif activationCondition == true then
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
                    styles = ThemeEngine.GetStyles(),
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
                        styles = ThemeEngine.GetStyles(),
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
                            gui.Button{
                                classes = {"deleteButton", "sizeXs"},
                                halign = "right",
                                valign = "center",
                                click = function()
                                    table.remove(skills, i)
                                    Refresh()
                                end,
                            },
                        }
                    end
                end

                children[#children+1] = gui.Dropdown{
                    styles = ThemeEngine.GetStyles(),
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
                    styles = ThemeEngine.GetStyles(),
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
                            id = "epic",
                            text = "Epic Resources",
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
                    styles = ThemeEngine.GetStyles(),
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
                        styles = ThemeEngine.GetStyles(),
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
                    styles = ThemeEngine.GetStyles(),
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
                    styles = ThemeEngine.GetStyles(),
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
						{
							id = "condition_after_roll",
							text = "Conditional After Power Roll",
						},
					},
					change = function(element)
						if element.idChosen ~= conditionType then
							if element.idChosen == "never" then
								modifier.activationCondition = false
								modifier.activationAfterRoll = false
							elseif element.idChosen == "always" then
								modifier.activationCondition = true
								modifier.activationAfterRoll = false
							elseif element.idChosen == "condition" then
								modifier.activationCondition = ""
								modifier.activationAfterRoll = false
							else -- condition_after_roll
								modifier.activationCondition = false
								modifier.activationAfterRoll = ""
								modifier.displayAfterRoll = ""
							end
							Refresh()
						end
					end,
				}

			}

            if activationCondition ~= true and activationCondition ~= false then
                local helpSymbols = CharacterModifier.defaultHelpSymbols
                if modifier.rollType == "ability_power_roll" or modifier.rollType == "enemy_ability_power_roll" then
                    helpSymbols = g_powerRollSymbols
                end

                helpSymbols = DeepCopy(helpSymbols)
                helpSymbols.cast = {
                    name = "Cast",
                    type = "spellcast",
                    desc = "The cast info for this ability",
                }
                helpSymbols.title = {
                    name = "Title",
                    type = "text",
                    desc = "The title of the roll",
                    examples = "Recall Lore Test to Recall Location of Amulet",
                }
                helpSymbols.rollcharacteristic = {
                    name = "Roll Characteristic",
                    type = "number",
                    desc = "The value of the characteristic used for this roll, e.g. 2 for a Might +2 roll. Absent if the roll uses no characteristic.",
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
					value = activationCondition,
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
            elseif conditionType == "condition_after_roll" then
                local helpSymbols = CharacterModifier.defaultHelpSymbols
                if modifier.rollType == "ability_power_roll" or modifier.rollType == "enemy_ability_power_roll" then
                    helpSymbols = g_powerRollSymbols
                end

                helpSymbols = DeepCopy(helpSymbols)
                helpSymbols.cast = {
                    name = "Cast",
                    type = "spellcast",
                    desc = "The cast info for this ability. After the roll, cast.roll contains the dice total and cast.tier contains the tier result (1, 2, or 3).",
                }
                helpSymbols.title = {
                    name = "Title",
                    type = "text",
                    desc = "The title of the roll",
                    examples = "Recall Lore Test to Recall Location of Amulet",
                }

                children[#children+1] = gui.GoblinScriptInput{
                    placeholderText = "Enter display criteria...",
                    value = modifier:try_get("displayAfterRoll", ""),
                    change = function(element)
                        modifier.displayAfterRoll = element.value
                        Refresh()
                    end,

                    documentation = {
                        domains = modifier:Domains(),
                        help = "This GoblinScript is evaluated after the dice are rolled to determine whether this modifier is shown as an option. Use cast.roll for the dice total and cast.tier for the tier (1, 2, or 3).",
                        output = "boolean",
                        examples = {
                        },
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature affected by this modifier",
                        symbols = modifier:HelpAdditionalSymbols(helpSymbols),
                    },
                }

                children[#children+1] = gui.GoblinScriptInput{
                    placeholderText = "Enter after-roll activation criteria...",
                    value = modifier:try_get("activationAfterRoll", ""),
                    change = function(element)
                        modifier.activationAfterRoll = element.value
                        Refresh()
                    end,

                    documentation = {
                        domains = modifier:Domains(),
                        help = "This GoblinScript is evaluated after the dice are rolled to determine whether this modifier is applied. It sets the default checked state of the checkbox that appears in the post-roll window. Use cast.roll for the dice total and cast.tier for the tier (1, 2, or 3). The player can always override the value manually.",
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
                    styles = ThemeEngine.GetStyles(),
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
                    styles = ThemeEngine.GetStyles(),
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

            local resistanceHelpSymbols = DeepCopy(g_powerRollSymbols)
            resistanceHelpSymbols.resistance = {
                name = "Resistance",
                type = "number",
                desc = "The target's base characteristic value for potency resistance.",
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Modify Resistance:",
                },

                gui.GoblinScriptInput{
                    value = modifier:try_get("resistanceFormula", ""),
                    change = function(element)
                        modifier.resistanceFormula = element.value
                        Refresh()
                    end,

                    documentation = {
                        domains = modifier:Domains(),
                        help = "Formula for the target's effective characteristic value during potency resistance checks. Use 'resistance' to reference the base characteristic value. Leave blank for no modification.",
                        output = "number",
                        examples = {
                            {script = "min(6, resistance + 1)", text = "Add 1 to the characteristic, capped at 6"},
                            {script = "resistance + 2", text = "Add 2 to the characteristic (no cap)"},
                            {script = "max(3, resistance)", text = "Characteristic is at least 3"},
                        },
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature affected by this modifier",
                        symbols = modifier:HelpAdditionalSymbols(resistanceHelpSymbols),
                    },
                }
            }

            if options.triggered then
                children[#children+1] = gui.Check{
                    styles = ThemeEngine.GetStyles(),
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
                            styles = ThemeEngine.GetStyles(),
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

                    --Reasoned retarget filters: in addition to the all-inclusive
                    --filter above, these mark a target as invalid (with a reason
                    --surfaced to the user as a tooltip) rather than hiding it.
                    local reasonedFilters = modifier:try_get("changeTargetReasonedFilters", {})

                    if #reasonedFilters > 0 then
                        children[#children+1] = gui.Label{
                            classes = {"formLabel"},
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            tmargin = 6,
                            text = "Reasoned Filters:",
                        }
                    end

                    for index,reasonedFilter in ipairs(reasonedFilters) do
                        children[#children+1] = gui.Panel{
                            classes = {"formPanel"},
                            gui.Label{
                                classes = {"formLabel"},
                                text = "Filter:",
                            },
                            gui.GoblinScriptInput{
                                value = reasonedFilter.formula or "",
                                change = function(element)
                                    reasonedFilter.formula = element.value
                                    Refresh()
                                end,

                                documentation = {
                                    domains = modifier:Domains(),
                                    help = "A target that fails this GoblinScript is still shown but cannot be selected, and the reason below is surfaced to the user as a tooltip.",
                                    output = "boolean",
                                    examples = {
                                    },
                                    subject = creature.helpSymbols,
                                    subjectDescription = "The potential new target of the power roll.",
                                    symbols = helpSymbols,
                                },
                            },
                            gui.Button{
                                classes = {"deleteButton", "sizeXs"},
                                halign = "right",
                                valign = "center",
                                x = 30,
                                press = function()
                                    table.remove(reasonedFilters, index)
                                    modifier.changeTargetReasonedFilters = reasonedFilters
                                    Refresh()
                                end,
                            },
                        }

                        children[#children+1] = gui.Panel{
                            classes = {"formPanel"},
                            gui.Label{
                                classes = {"formLabel"},
                                text = "Reason:",
                            },
                            gui.Input{
                                classes = {"formInput"},
                                width = 300,
                                characterLimit = 200,
                                placeholderText = "Enter reason...",
                                text = reasonedFilter.reason or "",
                                change = function(element)
                                    reasonedFilter.reason = element.text
                                    Refresh()
                                end,
                            },
                        }
                    end

                    children[#children+1] = gui.Button{
                        width = "auto",
                        height = "auto",
                        minWidth = 220,
                        hpad = 16,
                        vpad = 6,
                        borderBox = true,
                        fontSize = 16,
                        halign = "left",
                        text = "Add Reasoned Filter",
                        click = function(element)
                            modifier.changeTargetReasonedFilters = modifier:try_get("changeTargetReasonedFilters", {})
                            modifier.changeTargetReasonedFilters[#modifier.changeTargetReasonedFilters+1] = {
                                formula = "",
                                reason = "",
                            }
                            Refresh()
                        end,
                    }

                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Retarget Effect:",
                        },

                        gui.Dropdown{
                            styles = ThemeEngine.GetStyles(),
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
                        styles = ThemeEngine.GetStyles(),
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
                    styles = ThemeEngine.GetStyles(),
                    options = {
                        {
                            id = "full",
                            text = "Full Damage",
                        },
                        {
                            id = "half",
                            text = "Half Damage",
                        },
                        {
                            id = "none",
                            text = "No Damage",
                        }
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
                styles = ThemeEngine.GetStyles(),
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
                styles = ThemeEngine.GetStyles(),
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

                local source = dropdownSourceType.idChosen
                local destType = dropdownDestType.idChosen

                --A source may map to multiple candidate destinations; the user
                --chooses between them at roll time. Single mappings stay stored
                --as a plain string for compatibility with existing content.
                local mappings = modifier:get_or_add("damageTypeMappings", {})
                local existing = mappings[source]
                if existing == nil then
                    mappings[source] = destType
                elseif type(existing) == "table" then
                    local found = false
                    for _,d in ipairs(existing) do
                        if d == destType then
                            found = true
                            break
                        end
                    end
                    if not found then
                        existing[#existing+1] = destType
                    end
                elseif existing ~= destType then
                    mappings[source] = {existing, destType}
                end
                Refresh()
            end

            local damageTypeChildren = {}

            for k,v in sorted_pairs(modifier:try_get("damageTypeMappings", {})) do
                for _,destType in ipairs(CharacterModifier.DamageMappingDestinations(v)) do
                    damageTypeChildren[#damageTypeChildren+1] = gui.Label{
                        text = string.format("%s -> %s", k, destType),
                        width = "auto",
                        height = "auto",
                        fontSize = 14,
                        gui.Button{
                            classes = {"deleteButton", "sizeXxs"},
                            styles = ThemeEngine.GetStyles(),
                            x = 12,
                            halign = "right",
                            valign = "center",
                            press = function()
                                local mappings = modifier.damageTypeMappings
                                local dests = {}
                                for _,d in ipairs(CharacterModifier.DamageMappingDestinations(mappings[k])) do
                                    if d ~= destType then
                                        dests[#dests+1] = d
                                    end
                                end
                                if #dests == 0 then
                                    mappings[k] = nil
                                elseif #dests == 1 then
                                    mappings[k] = dests[1]
                                else
                                    mappings[k] = dests
                                end
                                Refresh()
                            end,
                        },
                    }
                end
            end

            damageTypeChildren[#damageTypeChildren+1] = gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                classes = {cond(modifier.rollType == "project_roll", "collapsed-anim")},

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
                    halign = "left",
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
                    styles = ThemeEngine.GetStyles(),
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
                    styles = ThemeEngine.GetStyles(),
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
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    flow = "vertical",
                    create = function(element)
                        local children = {}
                        local adjustments = modifier:try_get("adjustments", {})
                        for i,adjustment in ipairs(adjustments) do
                            local panel = gui.Panel{
                                flow = "horizontal",
                                width = "auto",
                                height = 30,
                                halign = "left",
                                gui.Dropdown{
                                    styles = ThemeEngine.GetStyles(),
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
                                        {
                                            id = "any",
                                            text = "any",
                                        },
                                    },
                                    idChosen = adjustment.type,
                                    change = function(element)
                                        adjustments[i].type = element.idChosen
                                        Refresh()
                                    end,
                                },

                                gui.Dropdown{
                                    styles = ThemeEngine.GetStyles(),
                                    width = 110,
                                    halign = "left",
                                    options = {
                                        {
                                            id = "add",
                                            text = "add",
                                        },
                                        {
                                            id = "multiply",
                                            text = "multiply",
                                        },
                                    },
                                    idChosen = adjustment.operation or "add",
                                    change = function(element)
                                        adjustments[i].operation = element.idChosen
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

                                gui.Button{
                                    classes = {"deleteButton", "sizeXs"},
                                    valign = "center",
                                    lmargin = 8,
                                    click = function()
                                        table.remove(adjustments, i)
                                        Refresh()
                                    end,
                                }
                            }

                            children[#children+1] = panel
                        end

                        children[#children+1] = gui.Button{
                            classes = {"addButton", "sizeXs"},
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

            --Replace Forced Movement: rewrites the movement-type word in each tier
            --(e.g. push -> slide). Stored as modifier.replaceForcedMovement = {from=, to=}.
            local replaceForcedMovement = modifier:try_get("replaceForcedMovement")
            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(modifier.rollType == "project_roll", "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Replace Movement:",
                },
                gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = 30,
                    halign = "left",
                    gui.Dropdown{
                        styles = ThemeEngine.GetStyles(),
                        width = 110,
                        halign = "left",
                        textDefault = "(none)",
                        options = {
                            { id = "none", text = "(none)"},
                            { id = "any", text = "any"},
                            { id = "push", text = "push"},
                            { id = "pull", text = "pull"},
                            { id = "slide", text = "slide"},
                        },
                        idChosen = (replaceForcedMovement and replaceForcedMovement.from) or "none",
                        change = function(element)
                            if element.idChosen == "none" then
                                modifier.replaceForcedMovement = nil
                            else
                                local r = modifier:get_or_add("replaceForcedMovement", {})
                                r.from = element.idChosen
                                r.to = r.to or "slide"
                            end
                            Refresh()
                        end,
                    },
                    gui.Label{
                        text = "->",
                        textAlignment = "center",
                        halign = "center",
                        valign = "center",
                        fontSize = 22,
                        width = 40,
                        height = "auto",
                    },
                    gui.Dropdown{
                        styles = ThemeEngine.GetStyles(),
                        width = 110,
                        halign = "left",
                        classes = {cond(replaceForcedMovement == nil, "collapsed")},
                        options = {
                            { id = "push", text = "push"},
                            { id = "pull", text = "pull"},
                            { id = "slide", text = "slide"},
                        },
                        idChosen = (replaceForcedMovement and replaceForcedMovement.to) or "slide",
                        change = function(element)
                            local r = modifier:get_or_add("replaceForcedMovement", {})
                            r.to = element.idChosen
                            r.from = r.from or "push"
                            Refresh()
                        end,
                    },
                },
            }

            local hasVerticalAdjustment = false
            for _,adj in ipairs(modifier:try_get("adjustments", {})) do
                if adj.type == "push" or adj.type == "pull" or adj.type == "slide" then
                    hasVerticalAdjustment = true
                    break
                end
            end

            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(not hasVerticalAdjustment, "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "",
                },
                gui.Check{
                    styles = ThemeEngine.GetStyles(),
                    style = {
                        height = 30,
                        width = 160,
                        fontSize = 18,
                        halign = "left",
                    },
                    text = "Add Vertical",
                    value = modifier:try_get("vertical", false),
                    change = function(element)
                        modifier.vertical = element.value
                        Refresh()
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

            --Optional opt-in: also fire the "Add to Table" rule on the owning
            --creature's free strikes (which resolve as flat damage and skip
            --the power-roll modifier pipeline). The activation condition and
            --keyword filters above still gate the modifier per free strike.
            --Hidden when addText is empty since there's nothing to add.
            local addTextTrimmed = trim(modifier:try_get("addText", ""))
            local hideApplyToFreeStrikes = (modifier.rollType == "project_roll") or (addTextTrimmed == "")
            children[#children+1] = gui.Panel{
                classes = {"formPanel", cond(hideApplyToFreeStrikes, "collapsed-anim")},
                gui.Label{
                    classes = {"formLabel"},
                    text = "",
                },
                gui.Check{
                    styles = ThemeEngine.GetStyles(),
                    style = {
                        height = 30,
                        width = 260,
                        fontSize = 18,
                        halign = "left",
                    },
                    text = "Also Apply to Monster Free Strikes",
                    value = modifier:try_get("applyToFreeStrikes", false),
                    hover = function(element)
                        gui.Tooltip("When checked, this modifier's 'Add to Table' rule will also fire when the creature uses a free strike (monster or companion). The modifier's activation condition and keyword filters still gate it.")(element)
                    end,
                    change = function(element)
                        modifier.applyToFreeStrikes = element.value
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel", "formPanel-inline", cond(modifier.rollType == "project_roll", "collapsed-anim")},
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
                    styles = ThemeEngine.GetStyles(),
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
                    children[#children+1] = gui.Button{
                        classes = {"sizeL"},
                        halign = "left",
                        width = 220,
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
                styles = ThemeEngine.GetStyles(),
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
				children[#children+1] = gui.Button{
                    classes = {"sizeL"},
					halign = "left",
					width = 220,
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

function CharacterModifier:ShouldShowInPowerRollDialogAfter(modContext, creature, rollType, options)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    local shouldShow = typeInfo.shouldShowInPowerRollDialogAfterRoll
    if shouldShow ~= nil then
        self:InstallSymbolsFromContext(modContext)
        self:InstallSymbolsFromContext(options)
        return shouldShow(self, creature, rollType, nil, options)
    end
    return false
end

function CharacterModifier:DescribeModifyPowerRollAfter(modContext, creature, rollType, options)
    if self:ShouldShowInPowerRollDialogAfter(modContext, creature, rollType, options) then
        return {
            modifier = self,
            context = modContext,
        }
    end
    return nil
end

function CharacterModifier:HintModifyPowerRollsAfter(modContext, creature, rollType, options)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    local hint = typeInfo.hintPowerRollAfter
    if hint ~= nil then
        self:InstallSymbolsFromContext(modContext)
        self:InstallSymbolsFromContext(options)
        return hint(self, creature, rollType, options)
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

-- ============================================================
-- ABILITY CUSTOMISATION (CORE)
-- Allows players to personalise each ability on their character:
--   * Rename the ability (display only; original name preserved for GoblinScript)
--   * Override flavour text
--   * Add character speech variations (spoken when the ability is cast)
--   * Add a flat damage bonus and/or potency bonus (via ModifyPowerRoll)
--   * Adjust range fields based on the ability's targeting type
--
-- Data is stored per-character in creature.abilityCustomisations,
-- keyed by the lower-cased original ability name.  The dialog is opened
-- from the character sheet via ActivatedAbility:ShowCustomisationDialog.
-- ============================================================

-- Default field on creature: per-ability customisation overrides.
-- Keyed by lower-cased original ability name; values are plain tables.
creature.abilityCustomisations = {}

-- ---------------------------------------------------------------------------
-- CharacterModifier type: abilitycustomisation
-- ---------------------------------------------------------------------------
CharacterModifier.RegisterType('abilitycustomisation', 'Ability Customisation')

CharacterModifier.TypeInfo.abilitycustomisation = {
    init = function(modifier)
    end,

    -- willModifyAbility is only called from SynthesizeAbilities (cast-spell
    -- behavior) and is not on the hot path for GetActivatedAbilities.
    -- Return true conservatively; all gate logic lives in modifyAbility.
    willModifyAbility = function(modifier, creature, ability)
        return true
    end,

    modifyAbility = function(modifier, creature, ability)
        local customisations = modifier:try_get("_tmp_customisations")
        if customisations == nil then return ability end

        -- Key by original name in case another modifier renamed the ability first.
        local key = string.lower(ability.name)
        local origName = ability:try_get("_tmp_originalName")
        if origName ~= nil then key = string.lower(origName) end

        local data = customisations[key]
        if data == nil then return ability end

        local displayName     = data.displayName      or ""
        local flavorText      = data.flavorText        or ""
        local variations      = data.variations        or {}
        local damageBonus     = data.damageBonus       or 0
        local potencyBonus    = data.potencyBonus      or 0
        local rangeBonus      = data.rangeBonus        or 0
        local burstBonus      = data.burstBonus        or 0
        local cubeBonus       = data.cubeBonus         or 0
        local cubeWithinBonus = data.cubeWithinBonus   or 0
        local lineLengthBonus = data.lineLengthBonus   or 0
        local lineWidthBonus  = data.lineWidthBonus    or 0
        local lineWithinBonus = data.lineWithinBonus   or 0

        local hasChange =
            displayName ~= "" or flavorText ~= "" or #variations > 0
            or damageBonus ~= 0 or potencyBonus ~= 0
            or rangeBonus ~= 0 or burstBonus ~= 0
            or cubeBonus ~= 0 or cubeWithinBonus ~= 0
            or lineLengthBonus ~= 0 or lineWidthBonus ~= 0 or lineWithinBonus ~= 0
        if not hasChange then return ability end

        ability = ability:MakeTemporaryClone()

        -- Display name override (original preserved for GoblinScript).
        if displayName ~= "" then
            ability._tmp_originalName = ability:try_get("_tmp_originalName") or ability.name
            ability.name = displayName
        end

        -- Flavor text override.
        if flavorText ~= "" then
            ability.flavor = flavorText
        end

        -- Character speech (spoken when cast; applyto="caster" targets self).
        if #variations > 0 then
            local speechBehavior = ActivatedAbilityCharacterSpeechBehavior.new{
                applyto    = "caster",
                variations = DeepCopy(variations),
            }
            ability.behaviors[#ability.behaviors+1] = speechBehavior
        end

        -- Damage / potency via ActivatedAbilityModifyPowerRollBehavior.
        if damageBonus ~= 0 or potencyBonus ~= 0 then
            local behaviorGuid = dmhub.GenerateGuid()
            local powerMod = CharacterModifier.new{
                guid        = dmhub.GenerateGuid(),
                sourceguid  = behaviorGuid,
                name        = "Ability Customisation",
                description = "",
                behavior    = "power",
                domains     = {},
            }
            CharacterModifier.TypeInfo.power.init(powerMod)
            powerMod.rollType            = "ability_power_roll"
            powerMod.activationCondition = true
            if damageBonus ~= 0 then
                powerMod.damageModifier = tostring(damageBonus)
            end
            if potencyBonus ~= 0 then
                powerMod.potencymod = tostring(potencyBonus)
            end
            ability.behaviors[#ability.behaviors+1] = ActivatedAbilityModifyPowerRollBehavior.new{
                guid     = behaviorGuid,
                modifier = powerMod,
            }
        end

        -- Range adjustments (spinner values are in squares; convert to world units).
        local ups = dmhub.unitsPerSquare
        local tt  = ability:try_get("targetType", "")
        if tt == "all" then
            -- Burst: radius is stored in ability.range.
            if burstBonus ~= 0 then
                ability.range = (ability.range or ups) + burstBonus * ups
            end
        elseif tt == "cube" then
            -- Cube: edge size in ability.radius, within distance in ability.range.
            if cubeBonus ~= 0 then
                ability.radius = (ability.radius or ups) + cubeBonus * ups
            end
            if cubeWithinBonus ~= 0 then
                ability.range = (ability.range or ups) + cubeWithinBonus * ups
            end
        elseif tt == "line" then
            -- Line: length in ability.range, width in ability.radius,
            --       within in ability.lineDistance (squares, not world units).
            if lineLengthBonus ~= 0 then
                ability.range = (ability.range or ups) + lineLengthBonus * ups
            end
            if lineWidthBonus ~= 0 then
                ability.radius = (ability.radius or ups) + lineWidthBonus * ups
            end
            if lineWithinBonus ~= 0 then
                ability.lineDistance = (ability.lineDistance or 1) + lineWithinBonus
            end
        else
            -- Melee, ranged, self, etc.: standard range field.
            if rangeBonus ~= 0 then
                ability.range = (ability.range or ups) + rangeBonus * ups
            end
        end

        return ability
    end,

    createEditor = function(modifier, element)
        -- Customisation is accessed through ShowCustomisationDialog, not an
        -- inline modifier editor.  Nothing needed here.
    end,
}

-- ---------------------------------------------------------------------------
-- Inject the customisation modifier into every creature's modifier pipeline
-- whenever creature.abilityCustomisations is non-empty.
-- ---------------------------------------------------------------------------
creature.RegisterFeatureCalculation{
    id = "abilitycustomisation_core",
    FillFeatures = function(c, features)
        local customisations = c:try_get("abilityCustomisations") or {}
        if next(customisations) == nil then return end

        local modifier = CharacterModifier.new{
            guid     = "abilitycustomisation_core",
            name     = "Ability Customisation",
            behavior = "abilitycustomisation",
        }
        -- _tmp_ prefix: transient, not serialized.  Rebuilt each cycle.
        modifier._tmp_customisations = customisations

        local pseudoFeature = {
            FillModifiers = function(self, creature, result)
                result[#result+1] = { mod = modifier }
            end,
        }
        features[#features+1] = pseudoFeature
    end,
}

-- ---------------------------------------------------------------------------
-- Compatibility patches
-- Guards prevent double-application when the external
-- Character_Ability_Customisation_e94f mod is also installed.
-- ---------------------------------------------------------------------------

-- Patch 1: GoblinScript Ability.Name returns the pre-rename name.
if not rawget(_G, "g_abilityCust_namePatchApplied") then
    _G.g_abilityCust_namePatchApplied = true
    local _origLookupName = ActivatedAbility.lookupSymbols.name
    ActivatedAbility.lookupSymbols.name = function(c)
        local orig = c:try_get("_tmp_originalName")
        if orig ~= nil then return orig end
        return _origLookupName(c)
    end
end

-- Patch 2: Named invoke lookup can find renamed abilities by temporarily
-- restoring original names during GetActivatedAbilities.
if not rawget(_G, "g_abilityCust_invokePatchApplied") then
    _G.g_abilityCust_invokePatchApplied = true

    local g_invokeLookupActive = false

    local _origGetActivatedAbilities = creature.GetActivatedAbilities
    function creature:GetActivatedAbilities(options)
        local abilities = _origGetActivatedAbilities(self, options)
        if g_invokeLookupActive then
            for _, ab in ipairs(abilities) do
                local orig = ab:try_get("_tmp_originalName")
                if orig ~= nil then ab.name = orig end
            end
        end
        return abilities
    end

    local _origInvokeCast = ActivatedAbilityInvokeAbilityBehavior.Cast
    function ActivatedAbilityInvokeAbilityBehavior:Cast(ability, casterToken, targets, options)
        local wasActive = g_invokeLookupActive
        if self.abilityType == "named" then g_invokeLookupActive = true end
        local result = _origInvokeCast(self, ability, casterToken, targets, options)
        g_invokeLookupActive = wasActive
        return result
    end

    local _origInvocationInvoke = AbilityInvocation.Invoke
    function AbilityInvocation:Invoke()
        local wasActive = g_invokeLookupActive
        if self.abilityType == "named" then g_invokeLookupActive = true end
        local result = _origInvocationInvoke(self)
        g_invokeLookupActive = wasActive
        return result
    end
end

-- ---------------------------------------------------------------------------
-- Dialog: ActivatedAbility:ShowCustomisationDialog(token, parentPanel)
-- Opens a floating editor for personalising this ability on the given token.
-- Returns the dialog panel; caller should call parentPanel:AddChild(dialog).
-- ---------------------------------------------------------------------------

-- Helper: a horizontal row with an optional label and a tightly-packed
-- [-] [value] [+] spinner group.  getValue/setValue are zero-argument closures.
-- Returns a table { panel = <Panel>, sync = <function> } so callers can
-- force-refresh the displayed value (e.g. from a Reset button).
local function MakeSpinner(labelText, getValue, setValue)
    local valueLabel
    local function SyncLabel()
        if valueLabel ~= nil and valueLabel.valid then
            valueLabel.text = tostring(getValue())
        end
    end

    valueLabel = gui.Label{
        classes       = {"sizeM"},
        text          = tostring(getValue()),
        width         = 36,
        height        = 22,
        valign        = "center",
        textAlignment = "Center",
    }

    -- Pack [-] [value] [+] into a tight sub-panel so they stay together.
    local spinGroup = gui.Panel{
        flow   = "horizontal",
        width  = "auto",
        height = "auto",
        gui.Button{
            text   = "-",
            width  = 22,
            height = 22,
            press  = function()
                setValue(getValue() - 1)
                SyncLabel()
            end,
        },
        valueLabel,
        gui.Button{
            text   = "+",
            width  = 22,
            height = 22,
            press  = function()
                setValue(getValue() + 1)
                SyncLabel()
            end,
        },
    }

    local rowChildren = {}
    if labelText ~= nil and labelText ~= "" then
        rowChildren[#rowChildren+1] = gui.Label{
            classes = {"formLabel"},
            text    = labelText,
        }
    end
    rowChildren[#rowChildren+1] = spinGroup

    local row = gui.Panel{
        classes = {"formPanel"},
        width   = "100%",
    }
    row.children = rowChildren
    return { panel = row, sync = SyncLabel }
end

function ActivatedAbility:ShowCustomisationDialog(token, parentPanel)
    -- Use the original ability name (before any prior rename) as the storage key.
    local abilityOrigName = self:try_get("_tmp_originalName") or self.name
    local abilityKey      = string.lower(abilityOrigName)

    -- Load current saved data for this ability (may be empty/absent).
    local srcData = (token.properties:try_get("abilityCustomisations") or {})[abilityKey] or {}

    -- Working copy -- all edits stay here until "Save & Close" is pressed.
    local wd = {
        displayName      = srcData.displayName      or "",
        flavorText       = srcData.flavorText        or "",
        variations       = DeepCopy(srcData.variations       or {}),
        damageBonus      = srcData.damageBonus       or 0,
        potencyBonus     = srcData.potencyBonus      or 0,
        rangeBonus       = srcData.rangeBonus        or 0,
        burstBonus       = srcData.burstBonus        or 0,
        cubeBonus        = srcData.cubeBonus         or 0,
        cubeWithinBonus  = srcData.cubeWithinBonus   or 0,
        lineLengthBonus  = srcData.lineLengthBonus   or 0,
        lineWidthBonus   = srcData.lineWidthBonus    or 0,
        lineWithinBonus  = srcData.lineWithinBonus   or 0,
    }

    local targetType = self:try_get("targetType", "")

    -- Forward declarations (closures below capture these upvalues).
    local dialog
    local variationsContainer
    local variationsInner
    local RebuildVariations

    local function CloseDialog()
        if dialog ~= nil and dialog.valid then
            dialog:DestroySelf()
        end
        dialog = nil
    end

    local function SaveAndClose()
        local isEmpty =
            wd.displayName == "" and wd.flavorText == ""
            and #wd.variations == 0
            and wd.damageBonus == 0 and wd.potencyBonus == 0
            and wd.rangeBonus == 0 and wd.burstBonus == 0
            and wd.cubeBonus == 0 and wd.cubeWithinBonus == 0
            and wd.lineLengthBonus == 0 and wd.lineWidthBonus == 0
            and wd.lineWithinBonus == 0
        token:ModifyProperties{
            description = "Customize Ability",
            execute = function()
                local cust = DeepCopy(
                    token.properties:try_get("abilityCustomisations") or {}
                )
                if isEmpty then
                    cust[abilityKey] = nil
                else
                    cust[abilityKey] = wd
                end
                token.properties.abilityCustomisations = cust
            end,
        }
        CloseDialog()
    end

    -- Helper: build the list of variation input panels from wd.variations.
    -- Called at initial dialog build time AND by RebuildVariations after the
    -- dialog exists (e.g. when the user adds or removes a variation entry).
    local function BuildVariationChildren()
        local vChildren = {}
        for i, entry in ipairs(wd.variations) do
            local idx = i
            vChildren[#vChildren+1] = gui.Panel{
                classes = {"formPanel"},
                width   = "100%",
                gui.Input{
                    classes     = {"formInput"},
                    width       = 360,
                    height      = "auto",
                    minHeight   = 20,
                    maxHeight   = 140,
                    halign      = "left",
                    multiline   = true,
                    text        = entry,
                    change      = function(element)
                        wd.variations[idx] = element.text
                    end,
                },
                gui.Button{
                    classes = {"deleteButton"},
                    width   = 16,
                    height  = 16,
                    press   = function()
                        table.remove(wd.variations, idx)
                        RebuildVariations()
                    end,
                },
            }
        end
        -- Empty input for adding new variations.
        vChildren[#vChildren+1] = gui.Panel{
            classes = {"formPanel"},
            width   = "100%",
            gui.Input{
                classes         = {"formInput"},
                width           = 380,
                height          = "auto",
                minHeight       = 20,
                maxHeight       = 140,
                halign          = "left",
                multiline       = true,
                placeholderText = "Add new speech variation...",
                change          = function(element)
                    if element.text ~= "" then
                        wd.variations[#wd.variations+1] = element.text
                        RebuildVariations()
                    end
                end,
            },
        }
        return vChildren
    end

    -- RebuildVariations is only called AFTER the dialog exists (user interaction).
    -- By that point variationsInner is already parented, so setting its children
    -- does NOT cause variationsContainer to drift in the dialog's child list.
    RebuildVariations = function()
        variationsInner.children = BuildVariationChildren()
    end

    -- Build the initial children BEFORE creating variationsInner so we can
    -- pass them via the panel constructor (integer keys) rather than via the
    -- .children setter.  Setting .children on an unparented panel before it
    -- is used as a constructor argument triggers a DMHub internal ordering
    -- side-effect that mis-sorts variationsContainer within the dialog.
    local initVChildren = BuildVariationChildren()
    local variationsInnerProps = {
        flow   = "vertical",
        width  = "100%",
        height = "auto",
    }
    for i, child in ipairs(initVChildren) do
        variationsInnerProps[i] = child
    end
    variationsInner = gui.Panel(variationsInnerProps)

    -- Static outer wrapper: the header label never changes, so the whole
    -- variationsContainer is stable in the dialog's child list.
    variationsContainer = gui.Panel{
        width  = "100%",
        height = "auto",
        flow   = "vertical",
        gui.Label{
            classes = {"bold"},
            text    = "Character Speech",
            width   = "100%",
            vmargin = 4,
        },
        variationsInner,
    }

    -- Collect all spinner sync functions so ResetAll can refresh them.
    local spinnerSyncs = {}

    -- Build range spinners based on the ability's targeting type.
    local rangeRows = {}
    rangeRows[#rangeRows+1] = gui.Label{
        classes = {"bold"},
        text    = "Range",
        width   = "100%",
        vmargin = 4,
    }
    if targetType == "all" then
        local s = MakeSpinner("Burst Size Bonus:",
            function() return wd.burstBonus end, function(v) wd.burstBonus = v end)
        spinnerSyncs[#spinnerSyncs+1] = s.sync
        rangeRows[#rangeRows+1] = s.panel
    elseif targetType == "cube" then
        local s1 = MakeSpinner("Cube Size Bonus:",
            function() return wd.cubeBonus end, function(v) wd.cubeBonus = v end)
        local s2 = MakeSpinner("Within Bonus:",
            function() return wd.cubeWithinBonus end, function(v) wd.cubeWithinBonus = v end)
        spinnerSyncs[#spinnerSyncs+1] = s1.sync
        spinnerSyncs[#spinnerSyncs+1] = s2.sync
        rangeRows[#rangeRows+1] = s1.panel
        rangeRows[#rangeRows+1] = s2.panel
    elseif targetType == "line" then
        local s1 = MakeSpinner("Length Bonus:",
            function() return wd.lineLengthBonus end, function(v) wd.lineLengthBonus = v end)
        local s2 = MakeSpinner("Width Bonus:",
            function() return wd.lineWidthBonus end, function(v) wd.lineWidthBonus = v end)
        local s3 = MakeSpinner("Within Bonus:",
            function() return wd.lineWithinBonus end, function(v) wd.lineWithinBonus = v end)
        spinnerSyncs[#spinnerSyncs+1] = s1.sync
        spinnerSyncs[#spinnerSyncs+1] = s2.sync
        spinnerSyncs[#spinnerSyncs+1] = s3.sync
        rangeRows[#rangeRows+1] = s1.panel
        rangeRows[#rangeRows+1] = s2.panel
        rangeRows[#rangeRows+1] = s3.panel
    else
        local s = MakeSpinner("Range Bonus:",
            function() return wd.rangeBonus end, function(v) wd.rangeBonus = v end)
        spinnerSyncs[#spinnerSyncs+1] = s.sync
        rangeRows[#rangeRows+1] = s.panel
    end

    -- Forward-declare input panel refs so ResetAll can clear their text.
    local displayNameInput
    local flavorTextInput

    local function ResetAll()
        wd.displayName      = ""
        wd.flavorText       = ""
        wd.variations       = {}
        wd.damageBonus      = 0
        wd.potencyBonus     = 0
        wd.rangeBonus       = 0
        wd.burstBonus       = 0
        wd.cubeBonus        = 0
        wd.cubeWithinBonus  = 0
        wd.lineLengthBonus  = 0
        wd.lineWidthBonus   = 0
        wd.lineWithinBonus  = 0
        -- Refresh spinner value labels.
        for _, sync in ipairs(spinnerSyncs) do sync() end
        -- Clear text inputs.
        if displayNameInput ~= nil and displayNameInput.valid then
            displayNameInput.text = ""
        end
        if flavorTextInput ~= nil and flavorTextInput.valid then
            flavorTextInput.text = ""
        end
        -- Rebuild the speech variations section.
        RebuildVariations()
    end

    -- Damage & potency spinners.
    local dmgSpinner = MakeSpinner("Damage Bonus:",
        function() return wd.damageBonus end, function(v) wd.damageBonus = v end)
    local potSpinner = MakeSpinner("Potency Bonus:",
        function() return wd.potencyBonus end, function(v) wd.potencyBonus = v end)
    spinnerSyncs[#spinnerSyncs+1] = dmgSpinner.sync
    spinnerSyncs[#spinnerSyncs+1] = potSpinner.sync

    -- Assemble the dialog child list.
    local dChildren = {}

    -- Title row.
    dChildren[#dChildren+1] = gui.Panel{
        width   = "100%",
        height  = 36,
        flow    = "horizontal",
        halign  = "center",
        valign  = "center",
        gui.Label{
            classes = {"bold", "sizeXl"},
            text    = "Customize: " .. abilityOrigName,
        },
        gui.Button{
            classes  = {"closeButton"},
            floating = true,
            halign   = "right",
            valign   = "center",
            rmargin  = 4,
            press    = CloseDialog,
        },
    }

    -- Display name.
    displayNameInput = gui.Input{
        classes         = {"formInput"},
        width           = 330,
        height          = 26,
        lmargin         = 16,
        halign          = "right",
        text            = wd.displayName,
        placeholderText = "Leave blank to keep original name",
        change          = function(element)
            wd.displayName = element.text
        end,
    }
    dChildren[#dChildren+1] = gui.Panel{
        classes = {"formPanel"},
        width   = "100%",
        gui.Label{ classes = {"formLabel"}, text = "Display Name:" },
        displayNameInput,
    }

    -- Flavor text.
    flavorTextInput = gui.Input{
        classes         = {"formInput"},
        width           = 330,
        height          = "auto",
        minHeight       = 26,
        maxHeight       = 140,
        lmargin         = 16,
        halign          = "right",
        multiline       = true,
        text            = wd.flavorText,
        placeholderText = "Leave blank to keep original flavor text",
        change          = function(element)
            wd.flavorText = element.text
        end,
    }

    dChildren[#dChildren+1] = gui.Panel{
        classes = {"formPanel"},
        width   = "100%",
        gui.Label{ classes = {"formLabel"}, text = "Flavor Text:" },
        flavorTextInput,
    }

    -- Damage & potency section header.
    dChildren[#dChildren+1] = gui.Label{
        classes = {"bold"},
        text    = "Damage & Potency",
        width   = "100%",
        vmargin = 4,
    }
    dChildren[#dChildren+1] = dmgSpinner.panel
    dChildren[#dChildren+1] = potSpinner.panel

    -- Range rows.
    for _, row in ipairs(rangeRows) do
        dChildren[#dChildren+1] = row
    end

    -- Speech variations (pre-populated above; always second-to-last).
    dChildren[#dChildren+1] = variationsContainer

    -- Action buttons.
    dChildren[#dChildren+1] = gui.Panel{
        width   = "100%",
        height  = 50,
        halign  = "center",
        flow    = "horizontal",
        vmargin = 8,
        gui.Button{
            text   = "Save & Close",
            width  = 170,
            height = 34,
            press  = SaveAndClose,
        },
        gui.Button{
            text   = "Cancel",
            width  = 120,
            height = 34,
            press  = CloseDialog,
        },
        gui.Button{
            text    = "Reset All",
            width   = 110,
            height  = 34,
            lmargin = 12,
            press   = ResetAll,
        },
    }

    -- Construct the dialog panel from the assembled children list.
    local dialogProps = {
        styles    = ThemeEngine.GetStyles(),
        classes   = {"framedPanel"},
        floating  = true,
        halign    = "center",
        valign    = "center",
        width     = 540,
        height    = "auto",
        flow      = "vertical",
        pad       = 16,
        borderBox = true,
    }
    for i, child in ipairs(dChildren) do
        dialogProps[i] = child
    end
    dialog = gui.Panel(dialogProps)

    return dialog
end