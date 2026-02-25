local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityDrawSteelCommandBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field rule string GoblinScript rule expression executed when this behavior fires.
--- Executes a GoblinScript "rule" as part of the ability's power table effect resolution.
ActivatedAbilityDrawSteelCommandBehavior = RegisterGameType("ActivatedAbilityDrawSteelCommandBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityDrawSteelCommandBehavior.summary = 'Power Roll Effect'
ActivatedAbilityDrawSteelCommandBehavior.rule = ''

ActivatedAbility.RegisterType
{
    id = 'draw_steel_command',
    text = 'Power Table Effect',
    createBehavior = function()
        return ActivatedAbilityDrawSteelCommandBehavior.new{
        }
    end
}

function ActivatedAbilityDrawSteelCommandBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Rule: " .. self.rule
end


function ActivatedAbilityDrawSteelCommandBehavior:Cast(ability, casterToken, targets, options)
    local promptWhenResolving = self:try_get("promptWhenResolving", false)

    local targetChoices = {}
    if promptWhenResolving then
        for _,target in ipairs(targets or {}) do
            local targetToken = target.token
            targetChoices[#targetChoices+1] = targetToken
        end
    end

    --ability:CommitToPaying(casterToken, options)

    repeat
        if promptWhenResolving and #targets > 0 then

            targets = nil
            GameHud.instance.actionBarPanel:FireEventTree("chooseTargetToken", {
                sourceToken = casterToken,
                targets = table.shallow_copy(targetChoices),
                prompt = self:try_get("promptWhenResolvingText", "Choose Target"),
                choose = function(targetToken)
                    targets = {
                        {
                            token = targetToken,
                        }
                    }

                    for i=1,#targetChoices do
                        if targetChoices[i].charid == targetToken.charid then
                            table.remove(targetChoices, i)
                            break
                        end
                    end
                end,
                cancel = function()
                    targets = {}
                    targetChoices = {}
                end,
            })

            while targets == nil do
                coroutine.yield(0.1)
            end
        end

        for _,target in ipairs(targets) do
            if target.token ~= nil then
                local rule = StringInterpolateGoblinScript(self.rule, casterToken.properties)
                --print("INTERPOLATE::", self.rule, "->", rule)
                self:ExecuteCommand(ability, casterToken, target.token, options, rule)
            end
        end
    until promptWhenResolving == false or targetChoices == nil or #targetChoices == 0
end

local function InvokeAbilityRemote(standardAbilityName, targetToken, casterToken, abilityAttr, options)
    local invocation = AbilityInvocation.new{
        timestamp = ServerTimestamp(),
        userid = casterToken.activeControllerId,
        abilityType = "standard",
        standardAbility = standardAbilityName,
        targeting = "prompt",
        invokerid = casterToken.charid,
        casterid = targetToken.charid,
        symbols = options.symbols,
        abilityAttr = abilityAttr,
    }

    targetToken:ModifyProperties{
        description = "Invoke Ability",
        undoable = false,
        execute = function()
			local invokes = targetToken.properties:get_or_add("remoteInvokes", {})
			invokes[#invokes+1] = invocation
        end,
    }
end

local function InvokeAbility(ability, abilityClone, targetToken, casterToken, options)

    --record the targets in case we need them.
    abilityClone.recordTargets = true
    abilityClone.keywords = ability.keywords
    abilityClone.notooltip = true
    abilityClone.skippable = true

    local casting = false

    local symbols = { invoker = GenerateSymbols(casterToken.properties), upcast = options.symbols.upcast, charges = options.symbols.charges, cast = options.symbols.cast, spellname = options.symbols.spellname, forcedMovementOrigin = options.symbols.forcedMovementOrigin }
    local haveToPay = ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(casterToken, abilityClone, targetToken, (options.targetArgs and "args") or "prompt", symbols, options)
    if haveToPay then
        ability:CommitToPaying(casterToken, options)
    end
end

local function ExecuteDamage(behavior, ability, casterToken, targetToken, options, match)
    local damageType = match.type or "untyped"
    local damage = tonumber(match.damage)
    
    -- Count how many times (half) appears in the modifiers
    local halfCount = 0
    if match.mods then
        local _, count = string.gsub(match.mods, "half", "")
        halfCount = count
    end

    local noDamage = false
    if match.mods then
        local _, count = string.gsub(match.mods, "no damage", "")
        noDamage = count > 0
    end
    
    print("ExecuteDamage::", damage, damageType, "halfCount:", halfCount, "noDamage:", noDamage)

    if damage == nil then
        local complete = false
        local rollid
        rollid = GameHud.instance.rollDialog.data.ShowDialog{
            title = "Damage Roll",
            roll = match.damage,
            completeRoll = function(rollInfo)
                complete = true
                damage = rollInfo.total
            end,
            cancelRoll = function()
                complete = true
            end,
        }

        while not complete do
            coroutine.yield(0.1)
        end
    end

    local bonus = match.bonus
    if bonus ~= nil then
        bonus = regex.ReplaceAll(bonus, ",? or ", ", ")

        local items = regex.Split(bonus, ", *")

        bonus = nil

        for _,item in ipairs(items) do
            local attrid = GameSystem.AttributeByFirstLetter[string.lower(item)] or "-"
            if attrid ~= '-' then
                local newBonus = targetToken.properties:AttributeMod(attrid)
                if bonus == nil or newBonus > bonus then
                    bonus = newBonus
                end
            end
        end
    end


    if damage ~= nil then

        local attacker = casterToken.properties
        if options.symbols.targetPairs ~= nil then
            for _,pair in ipairs(options.symbols.targetPairs) do
                if pair.b == targetToken.charid then
                    local attackerTok = dmhub.GetTokenById(pair.a)
                    if attackerTok ~= nil then
                        attacker = attackerTok.properties
                    end
                end
            end
        end

        if bonus ~= nil then
            damage = damage + bonus
        end

        if halfCount > 0 then
            for i = 1, halfCount do
                damage = math.floor(damage/2)
            end
        end

        local selfName = creature.GetTokenDescription(casterToken)

        local result

        local damageMessage = string.format("%d %s damage", damage, damageType)
        if halfCount > 0 then
            local halfText = string.rep("(half) ", halfCount)
            damageMessage = damageMessage .. " " .. string.trim(halfText)
        end
        ability.RecordTokenMessage(targetToken, options, damageMessage)

        if not noDamage then
            targetToken:ModifyProperties{
                description = "Inflict Damage",
                undoable = false,
                execute = function()
                    result = targetToken.properties:InflictDamageInstance(damage, damageType, ability.keywords, string.format("%s's %s", selfName, ability.name), { criticalhit = false, attacker = attacker, surges = options.surges, ability = ability, hasability = true, cast = options.symbols.cast})
                    options.symbols.cast:CountDamage(targetToken, result.damageDealt, damage)
                end,
            }
        end
    end
end

local g_tablesLookup = {}

local function GetTableNameRegex(tableName, key, nameKey)
    nameKey = nameKey or "name"
    local table = dmhub.GetTable(tableName) or {}
    g_tablesLookup[tableName] = {}
    local pattern = ""
    for k,v in pairs(table) do
        if not v:try_get("hidden", false) and (key == nil or v:try_get(key, false)) then
            local name = regex.ReplaceAll(string.lower(v[nameKey]), "[^a-z0-9 ]", "")
            if name ~= "" then
                if pattern ~= "" then
                    pattern = pattern .. "|"
                end

                pattern = pattern .. name
                g_tablesLookup[tableName][name] = k
            end
        end
    end

    return pattern
end


local g_rulePatterns = {
    --[[
    --old style resistances. DEPRECATED
    {
        pattern = "^(?<attr>[MARIP]) ?(?<gate>(-?[0-9]+|\\[weak\\]|\\[average\\]|\\[strong\\]))",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            --see if the condition gate is exceeded.
            local gate
            if match.gate == "[weak]" then
                gate = casterToken.properties:HighestCharacteristic()-2
            elseif match.gate == "[average]" then
                gate = casterToken.properties:HighestCharacteristic()-1
            elseif match.gate == "[strong]" then
                gate = casterToken.properties:HighestCharacteristic()
            else
                gate = tonumber(match.gate)
            end


            local attrid = GameSystem.AttributeByFirstLetter[string.lower(match.attr)] or "-"
            local result = (targetToken.properties:AttributeForPotencyResistance(attrid) or 0) >= gate
            print("GATE:: RESULT =", result)
            return result
        end,
    },

    --new style resistances.
    {
        pattern = "^(?<attr>[MARIPmarip]) ?< ?\\[?(?<gate>(-?[0-9]+|weak|average|strong))(?:\\])?",
        execute = function(behavior, ability, casterToken, targetToken, options, match)

            --see if the condition gate is exceeded.
            local gate
            if match.gate == "weak" then
                gate = casterToken.properties:HighestCharacteristic()-2
            elseif match.gate == "average" then
                gate = casterToken.properties:HighestCharacteristic()-1
            elseif match.gate == "strong" then
                gate = casterToken.properties:HighestCharacteristic()
            else
                gate = tonumber(match.gate)
            end


            local attrid = GameSystem.AttributeByFirstLetter[string.lower(match.attr)] or "-"
            local result = (targetToken.properties:AttributeForPotencyResistance(attrid) or 0) >= gate
            print("GATE:: RESULT =", result)
            return result

        end,
    },
    --]]
    {
        pattern = {"^(?<damage>[0-9 d+-]+)\\s*(?<type>[a-z]+)?\\s?damage(?<mods>(\\s*\\(half\\))*)",
            "^(?<damage>[0-9]+)\\s+(?<type>[a-z]+)\\s+damage(?<mods>(\\s*\\(half\\))*)",
            "^(?<damage>[0-9]+)\\s*\\+\\s*(?<bonus>[a-z, ]+ or [a-z]+ )(?<type>[a-z]+)\\s*damage(?<mods>(\\s*\\(half\\))*)",
        },
        execute = ExecuteDamage,
        isdamage = true,
    },

    {
        pattern = "^(?<vertical>vertical )?(?<movement>pull|push|slide) +(?<straightup>straight up +)?(?<distance>[0-9]+)(?<ignorestability>[,;]? (ignoring stability|this (push|pull|slide) ignores the target.s stability))?",
        execute = function(behavior, ability, casterToken, targetToken, options, match)

            print("INVOKE:: EXECUTE FORCE MOVE", match.movement, match.distance)

            local ShowFailMessage = function(text)
                local abilityBase = MCDMUtils.GetStandardAbility("Float Text")
                if abilityBase then
                    local abilityClone = DeepCopy(abilityBase)
                    MCDMUtils.DeepReplace(abilityClone, "<<text>>", text)
                    InvokeAbility(ability, abilityClone, targetToken, targetToken, options)
                    ability:CommitToPaying(casterToken, options)
                end
            end

            local ShowFailSpeech = function(abilityName)
                local abilityBase = MCDMUtils.GetStandardAbility("Too Much Stability")
                if abilityBase then
                    InvokeAbility(ability, abilityBase, targetToken, targetToken, options)
                    ability:CommitToPaying(casterToken, options)
                end
            end

            local targetImmune = targetToken.properties:CalculateNamedCustomAttribute("Cannot Be Force Moved")
            if targetImmune > 0 then
                print("Target is immune to forced movement, not executing")
                ShowFailMessage("Immune to Forced Movement")
                return
            end

            local grabbedCondition = CharacterCondition.conditionsByName["grabbed"]
            if grabbedCondition ~= nil then
                local targetGrabbed = targetToken.properties:HasCondition(grabbedCondition.id)
                if targetGrabbed and targetGrabbed ~= casterToken.charid then
                    print("Target is grabbed, and cannot be force moved.")
                    ShowFailMessage("Grabbed: Cannot be Force Moved")
                    return
                end
            end


            local executeOnRemote = false
            if options.symbols.cast ~= nil then
                local startingCasterToken = casterToken
                targetToken, casterToken = options.symbols.cast:RemapForceMoveTargetAndCaster(targetToken, casterToken)
                if startingCasterToken ~= casterToken then
                    --retargeted.
                    executeOnRemote = true
                end
            end

            local adjustments = {}

            local sizeDifferenceBonus = 0
            if ability.keywords["Weapon"] and ability.keywords["Melee"] then
                local casterSize = casterToken.creatureSizeNumber
                local targetSize = targetToken.properties:CreatureSizeWhenBeingForceMoved()
                if casterSize > targetSize then
                    sizeDifferenceBonus = 1

                    --"Big Versus Little" is the name of the ability in the book.
                    adjustments[#adjustments+1] = string.format("Big Versus Little: +1")
                end
            end

            local stability = targetToken.properties:Stability()
            if stability ~= 0 and (match.ignorestability or casterToken.properties:CalculateNamedCustomAttribute("Ignore Stability") > 0) then
                stability = 0
                adjustments[#adjustments+1] = "Ignoring Stability"
            end

            local forcedMovementIncrease = targetToken.properties:CalculateNamedCustomAttribute("Forced Movement Increase")
            if forcedMovementIncrease > 0 then
                adjustments[#adjustments+1] = string.format("Forced Movement Increase: +%d", forcedMovementIncrease)
            end

            local forcedMovementBonus = casterToken.properties:ForcedMovementBonus(match.movement)
            if forcedMovementBonus > 0 then
                local describe = casterToken.properties:DescribeForcedMovementBonus(match.movement)
                local textItems = {}
                for _,entry in ipairs(describe) do
                    textItems[#textItems+1] = entry.key
                end

                if #textItems > 0 then
                    adjustments[#adjustments+1] = string.format("Forced Movement Bonus (%s): +%d", table.concat(textItems, ", "), forcedMovementBonus)
                end
            end

            local range = math.max(0, tonumber(match.distance) - stability + sizeDifferenceBonus + forcedMovementIncrease + forcedMovementBonus)

            if range <= 0 then
                --don't execute forced movement of 0?
                if stability > 0 then
                    ShowFailSpeech("Too Much Stability")
                else
                    ShowFailMessage("Cannot Be Force Moved")
                end
                return
            end

            local vertical = cond(match.vertical, "Vertical ", "")

            local abilityName = "Forced Movement: " .. vertical .. match.movement

            local description = string.format("You may %s the target %d square%s", match.movement, range, range > 1 and "s" or "")

            local abilityAttr = {
                name = string.gsub(match.movement, "^%l", string.upper) .. "!",
                range = range,
                description = description,
                invoker = casterToken.properties,
                promptOverride = description,
            }

            if stability > 0 then
                adjustments[#adjustments+1] = string.format("Stability: -%d", stability)
            end

            if #adjustments > 0 then
                abilityAttr.promptOverride = abilityAttr.promptOverride .. " (" .. table.concat(adjustments, ", ") .. ")"
            end

            if executeOnRemote and casterToken.activeControllerId then
                ability:CommitToPaying(casterToken, options)
                InvokeAbilityRemote(abilityName, targetToken, casterToken, abilityAttr, options)
            else
                local abilityClone = DeepCopy(MCDMUtils.GetStandardAbility(abilityName))
                MCDMUtils.DeepReplace(abilityClone, "<<range>>", string.format("%d", range))
                for k,v in pairs(abilityAttr) do
                    abilityClone[k] = v
                end

                if match.straightup then
                    options.targetArgs = {
                        {
                            loc = targetToken.loc:WithAltitude(targetToken.loc.altitude + range),
                        }
                    }
                end
                
                InvokeAbility(ability, abilityClone, targetToken, casterToken, options)
                options.targetArgs = nil
            end
        end,
    },
    {
        pattern = "^prone( and)? can't stand \\((?<duration>eot|eoe|save ends)\\)",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)

            local duration = string.lower(match.duration)
            if string.starts_with(duration, "save") then
                duration = "save"
            end

            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            for k,v in unhidden_pairs(conditionsTable) do
                if string.lower(v.name) == "prone" then

                    ability.RecordTokenMessage(targetToken, options, "Prone (Can't Stand)")
                    targetToken:ModifyProperties{
                        description = "Inflict Condition",
                        execute = function()
                            targetToken.properties:InflictCondition(k, {
                                duration = duration,
                                riders = {CharacterCondition.GetRiderIdFromName(k, "Cannot Stand")},
                                sourceDescription = string.format("Inflicted by %s's <b>%s</b> ability", creature.GetTokenDescription(casterToken), ability.name),
                                casterInfo = {
                                    tokenid = casterToken.charid,
                                },
                                cast = options.symbols.cast,
                            })
                        end
                    }
                    break
                end
            end
        end,

    },

    {
        pattern = "^(?<condition>bleeding|dazed|frightened|grabbed|prone|restrained|slowed|taunted|taunt|weakened) (?<effect>persists|ends at the end of your next turn|immediately ends)",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)
            if match.effect == "persists" then
                return
            end

            if match.condition == "taunt" then
                match.condition = "taunted"
            end

            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            for k,v in unhidden_pairs(conditionsTable) do
                if (not v:try_get("hidden", false)) and string.lower(v.name) == match.condition then
                    if targetToken.properties:HasCondition(k) then
                        ability.RecordTokenMessage(targetToken, options, string.format("%s removed", v.name))
                    end

                    targetToken:ModifyProperties{
                        description = "Remove Condition",
                        execute = function()
                            targetToken.properties:InflictCondition(k, {
                                force = true,
                                purge = match.effect == "immediately ends",
                                duration = "eot",
                                cast = options.symbols.cast,
                            })
                        end,
                    }
                    break
                end
            end
        end,
    },
    {
        pass = "caster",
        pattern = "^jump (?<distance>[0-9]+)",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)
            local jump = MCDMUtils.GetStandardAbility("Jump")

			local abilityClone = DeepCopy(jump)
            abilityClone.invoker = casterToken.properties

            local movedThisTurn = 0
            if casterToken.properties:IsOurTurn() then
                movedThisTurn = casterToken.properties:DistanceMovedThisTurn()
            end

            local movementAllowed = casterToken.properties:CurrentMovementSpeed() - movedThisTurn
            abilityClone.range = math.min(tonumber(match.distance), movementAllowed)

            local startingMovement = options.symbols.cast.spacesMoved
            InvokeAbility(ability, abilityClone, casterToken, casterToken, options)
            local jumpDistance = options.symbols.cast.spacesMoved - startingMovement

            if jumpDistance ~= 0 then
                casterToken:ModifyProperties{
                    description = "Jump Move Cost",
                    undoable = false,
                    execute = function()
                        if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                            return
                        end
                        casterToken.properties.moveDistance = casterToken.properties:DistanceMovedThisTurn() + jumpDistance
                        casterToken.properties.moveDistanceRoundId = dmhub.initiativeQueue:GetRoundId()
                    end,
                }
            end
        end,
    },
    {
        pattern = "^(?<condition>bleeding|dazed|frightened( of you)?|restrained|slowed|taunted|taunt|weakened)(?<additionalConditions>( and |,)[a-z ]+)? \\((?<duration>eot|EoT|save ends)?\\)",
        knownConditions = {"bleeding", "dazed", "frightened", "frightened of you", "grabbed", "restrained", "slowed", "taunted", "taunt", "weakened"},
        validate = function(entry, match)
            if match.additionalConditions == nil then
                return true
            end

            local additionalConditions = regex.Split(match.additionalConditions, "(,| and )")
            for _,c in ipairs(additionalConditions) do
                local cond = string.lower(trim(c))
                if cond == "" or cond == "," or cond == "and" then
                    --pass

                elseif not table.contains(entry.knownConditions, cond) then
                    return false
                end
            end

            return true
        end,
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)

            local mod = 0
            if match.condition == "taunt" then
                match.condition = "taunted"
            end
            if match.condition == "frightened of you" then
                match.condition = "frightened"
            end
            if match.save ~= nil then
                local attrid = string.lower(match.save)
                mod = targetToken.properties:AttributeMod(match.save)
            end

            local duration = string.lower(match.duration)
            if string.starts_with(duration, "save") then
                duration = "save"
            end

            local conditions = {match.condition}

            if match.additionalConditions ~= nil then
                local additionalConditions = regex.Split(match.additionalConditions, "(,| and )")
                for _,cond in ipairs(additionalConditions) do
                    local c = string.lower(trim(cond))
                    if c == "taunt" then
                        c = "taunted"
                    end

                    if c == "frightened of you" then
                        c = "frightened"
                    end

                    if c ~= "and" and c ~= "" and c ~= "," then
                        conditions[#conditions+1] = c
                    end
                end
            end

            for _,cond in ipairs(conditions) do

                targetToken:ModifyProperties{
                    description = "Inflict Condition",
                    execute = function()
                        local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
                        for k,v in unhidden_pairs(conditionsTable) do
                            if string.lower(v.name) == cond then
                                ability.RecordTokenMessage(targetToken, options, string.format("%s", v.name))
                                local riders = ability:GetRidersForCondition(k, casterToken, targetToken, options)
                                targetToken.properties:InflictCondition(k, {
                                    duration = duration,
                                    sourceDescription = string.format("Inflicted by %s's <b>%s</b> ability", creature.GetTokenDescription(casterToken), ability.name),
                                    casterInfo = {
                                        tokenid = casterToken.charid,
                                    },
                                    riders = riders,
                                    cast = options.symbols.cast,
                                })
                                break
                            end
                        end
                    end,
                }
            end
        end,
    },
    {
        pattern = "^(you )?swap places with the target",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)

            casterToken:SwapPositions(targetToken)
        end,
    },
    {
        pattern = "^[Gg]ain (?<amount>[0-9]+) (?<resource>piety|essence|ferocity|drama|discipline|insight|wrath|focus|clarity)",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)
            local quantity = tonumber(match.amount)
            local resourceInfo = dmhub.GetTable(CharacterResource.tableName)[CharacterResource.heroicResourceId]
            casterToken:ModifyProperties{
                description = "Gain " .. match.resource,
                execute = function()
                    --Allow Attribute Modification of HR amount
                    quantity = quantity + casterToken.properties:CalculateNamedCustomAttribute("Heroic Resource Gain Modification")
                    local num = casterToken.properties:RefreshResource(CharacterResource.heroicResourceId, resourceInfo.usageLimit, quantity, ability.name)
                    if options.symbols and options.symbols.cast then
                        options.symbols.cast.heroicresourcesgained = options.symbols.cast.heroicresourcesgained + num
                    end
                end,
            }
        end,
    },
    {
        pattern = "^the director gains (?<amount>[0-9]+) malice",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            local quantity = tonumber(match.amount)
            local malice = CharacterResource.GetMalice()
            malice = math.max(0, malice + quantity)
            CharacterResource.SetMalice(malice, ability.name)
        end,
    },
    {
        pass = "caster",
        pattern = "^(the [a-zA-Z]+ )?(you )?(can shift |shifts? (up to )?)(?<distance>[0-9]+)( squares?)?",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)

            local shiftDisabled = casterToken.properties:CalculateNamedCustomAttribute("Shift Disabled") > 0
            if shiftDisabled  then

                local abilityBase = MCDMUtils.GetStandardAbility("Float Text")
                if abilityBase then
                    local abilityClone = DeepCopy(abilityBase)
                    MCDMUtils.DeepReplace(abilityClone, "<<text>>", "Cannot Shift")
                    abilityClone.behaviors[1].color = "#FF0000"
                    InvokeAbility(ability, abilityClone, casterToken, casterToken, options)
                    ability:CommitToPaying(casterToken, options)
                end
                return
            end

            local movementSpeed = casterToken.properties:CurrentMovementSpeed()
            local distance = match.distance
            if movementSpeed < tonumber(distance) then
                distance = string.format("%d", movementSpeed)
                if movementSpeed <= 0 then
                    local abilityBase = MCDMUtils.GetStandardAbility("Float Text")
                    if abilityBase then
                        local abilityClone = DeepCopy(abilityBase)
                        MCDMUtils.DeepReplace(abilityClone, "<<text>>", "Cannot Move")
                        abilityClone.behaviors[1].color = "#FF0000"
                        InvokeAbility(ability, abilityClone, casterToken, casterToken, options)
                        ability:CommitToPaying(casterToken, options)
                    end
                    return
                end
            end



            local shift = MCDMUtils.GetStandardAbility("Shift")
			local abilityClone = DeepCopy(shift)
            AbilityUtils.DeepReplaceAbility(abilityClone, "<<targetfilter>>", "")
            AbilityUtils.DeepReplaceAbility(abilityClone, "<<distance>>", distance)
            abilityClone.invoker = casterToken.properties

            InvokeAbility(ability, abilityClone, casterToken, casterToken, options)
        end,
    },
    {
        pass = "caster",
        pattern = "^(the [a-zA-Z]+ )?(you )?teleports? (up to )?(?<distance>[0-9]+)( squares?)?",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)
            local teleport = MCDMUtils.GetStandardAbility("Teleport")

			local abilityClone = DeepCopy(teleport)
            abilityClone.invoker = casterToken.properties
            abilityClone.range = tonumber(match.distance)

            InvokeAbility(ability, abilityClone, casterToken, casterToken, options)
        end,
    },
    {
        pass = "caster",
        pattern = {"^a new target in (reach|range) takes +(?<damage>[0-9]+) +damage", "^a new target in (reach|range) takes (?<damage>[0-9]+) +(?<type>[a-z]+) +damage"},
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)
            local abilityClone = DeepCopy(MCDMUtils.GetStandardAbility("Target"))

            abilityClone.invoker = casterToken.properties
            abilityClone.range = ability.range
            abilityClone.targetFilter = string.format('target.id != "%s"', targetToken.charid)

            InvokeAbility(ability, abilityClone, casterToken, casterToken, options)

            if abilityClone:has_key("recordedTargets") then
                for _,target in ipairs(abilityClone.recordedTargets) do
                    if target.token ~= nil then
                        ExecuteDamage(behavior, ability, casterToken, target.token, options, match)
                    end

                end
            end


        end,
    },

    {
        pattern = "^(?<condition>prone|grabbed)",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)
            local cond = match.condition

            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            for k,v in unhidden_pairs(conditionsTable) do
                if string.lower(v.name) == cond then
                    ability.RecordTokenMessage(targetToken, options, string.format("%s", v.name))
                    local riders = ability:GetRidersForCondition(k, casterToken, targetToken, options)

                    targetToken:ModifyProperties{
                        description = "Inflict Condition",
                        execute = function()
                            targetToken.properties:InflictCondition(k, {
                                duration = "eoe",
                                riders = riders,
                                sourceDescription = string.format("Inflicted by %s's <b>%s</b> ability", creature.GetTokenDescription(casterToken), ability.name),
                                casterInfo = {
                                    tokenid = casterToken.charid,
                                },
                                cast = options.symbols.cast,
                            })
                        end
                    }
                    break
                end
            end
        end,

    },
    {
        pattern = "^teleport to opposite side",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)
            local GetAverageLocation = function(locs)
                local x, y = 0, 0
                for _,loc in ipairs(locs) do
                    x = x + loc.x
                    y = y + loc.y
                end
                return {x = x / #locs, y = y / #locs}
            end

            print("TELEPORT:: TRYING...")

            local casterLoc = GetAverageLocation(casterToken.locsOccupying)
            local targetLoc = GetAverageLocation(targetToken.locsOccupying)
            local dx = casterLoc.x - targetLoc.x
            local dy = casterLoc.y - targetLoc.y

            local originalLoc = targetToken.loc
            local targetLoc = originalLoc:dir(round(dx*2), round(dy*2))

            print("TELEPORT:: DOING...")
            targetToken:Teleport(targetLoc)
            print("TELEPORT:: DONE...")

            local t = dmhub.Time()
            for t=1,1000 do
                if dmhub.Time() > t + 0.3 then
                    break
                end
            end

            local newLoc = targetToken.loc
            if newLoc.x ~= targetLoc.x or newLoc.y ~= targetLoc.y then
                --we didn't teleport to the right place, so we undo the teleport.
                print("TELEPORT:: UNDOING...")
                targetToken:Teleport(originalLoc)
                return true --this tells it to stop processing more rules.
            else
                print("TELEPORT:: SUCCESS!")
            end
        end,
    }
}

function ActivatedAbility.RegisterPowerTableRule(args)
    local targetIndex = #g_rulePatterns+1
    if args.id ~= nil then
        for i=1,#g_rulePatterns do
            if g_rulePatterns[i].id == args.id then
                targetIndex = i
                break
            end
        end
    end

    g_rulePatterns[targetIndex] = args
end

local g_stringToNumber = {
    zero = 0,
    one = 1,
    two = 2,
    three = 3,
    four = 4,
    five = 5,
    six = 6,
    seven = 7,
    eight = 8,
    nine = 9,
    ten = 10,
}

local function StringToNumber(str)
    return g_stringToNumber[string.lower(str)] or tonumber(str) or 0
end

ActivatedAbility.RegisterPowerTableRule{
    --a unique ID which defines this rule.
    id = "targetgainssurges",

    --a regular expression that matches some text.
    pattern = "^(the|each)? ?target gains (?<quantity>one|two|three|four|five|six|[0-9]) surges?",

    --(optional) extra validation which can be done after matching the pattern.
    --- @param entry table A reference to this table, to easily access any properties.
    --- @param match table The match.
    --- @return boolean
    validate = function(entry, match)
        return true
    end,

    --once the text matches the pattern and passes validation we execute this to make the behavioe happen.
    --- @param behavior ActivatedAbilityBehavior
    --- @param ability ActivatedAbility
    --- @param casterToken CharacterToken
    --- @param targetToken CharacterToken
    --- @param options table
    --- @param match table
    execute = function(behavior, ability, casterToken, targetToken, options, match)
        local quantity = StringToNumber(match.quantity)
        targetToken:ModifyProperties{
            description = "Gain Surges",
            execute = function()
                targetToken.properties:RefreshResource(CharacterResource.surgeResourceId, "unbounded", quantity, string.format("%s used %s", casterToken.name, ability.name))
            end,
        }
    end,
}

local g_gainResourceIndex = nil
local g_applyConditionIndex = nil
local g_gainConditionWithRiderIndex = nil

dmhub.RegisterEventHandler("refreshTables", function(keys)
    if mod.unloaded then
        return
    end

	if keys ~= nil and (not keys[CharacterResource.tableName]) then
		return
	end


    g_gainConditionWithRiderIndex = g_gainConditionWithRiderIndex or #g_rulePatterns + 1
    g_rulePatterns[g_gainConditionWithRiderIndex] = {
        pattern = "^(?<rider>" .. GetTableNameRegex(CharacterCondition.ridersTableName, nil, "powerTableText") .. ")\\s+" .. "\\((?<duration>eot|eoe|save ends)\\)",
        execute = function(behavior, ability, casterToken, targetToken, options, match)

            local duration = string.lower(match.duration)
            if string.starts_with(duration, "save") then
                duration = "save"
            end

            local rider = match.rider
            local t = dmhub.GetTable(CharacterCondition.ridersTableName)
            local riderInfo = nil
            local riderid = nil
            for key,value in unhidden_pairs(t) do
                local name = regex.ReplaceAll(string.lower(value["powerTableText"]), "[^a-z0-9 ]", "")
                if name == string.lower(rider) then
                    riderid = key
                    riderInfo = value
                    break
                end
            end

            if riderInfo == nil then
                print("Rider:: Could not find rider for", rider)
                return
            end

            print("Rider:: Matched rider", rider)
            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            local conditionInfo = conditionsTable[riderInfo.condition]
            if conditionInfo == nil then
                print("Rider:: Could not find condition for rider", rider)
                return
            end

            targetToken:ModifyProperties {
                description = "Inflict Condition",
                execute = function()

                    targetToken.properties:InflictCondition(riderInfo.condition, {
                        duration = duration,
                        riders = {riderid},
                        sourceDescription = string.format("Inflicted by %s's <b>%s</b> ability", creature.GetTokenDescription(casterToken), ability.name),
                        casterInfo = {
                            tokenid = casterToken.charid,
                        },
                        cast = options.symbols.cast,
                    })
                end
            }
        end,
    }

    g_gainResourceIndex = g_gainResourceIndex or #g_rulePatterns + 1

    g_rulePatterns[g_gainResourceIndex] = {
        pattern = "^[Gg]ain +(?<amount>[0-9]+) +(?<resource>" .. GetTableNameRegex(CharacterResource.tableName) .. ")",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            local amount = tonumber(match.amount)
            local resource = match.resource

            local key = g_tablesLookup[CharacterResource.tableName][string.lower(resource)]
            if key ~= nil then
                targetToken:ModifyProperties{
                    description = "Gain Resource",
                    execute = function()
                        targetToken.properties:RefreshResource(key, "unbounded", amount, string.format("Gained %d %s from %s", amount, resource, ability.name))
                    end,
                }
            end
        end,
    }

    g_applyConditionIndex = g_applyConditionIndex or #g_rulePatterns + 1

    g_rulePatterns[g_applyConditionIndex] = {
        pattern = "^(?<condition>" .. GetTableNameRegex(CharacterCondition.tableName, "powertable") .. ") \\((?<duration>eot|EoT|save ends|eoe)?\\)",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            local duration = string.lower(match.duration)
            if string.starts_with(duration, "save") then
                duration = "save"
            end


            local cond = match.condition
            targetToken:ModifyProperties {
                description = "Inflict Condition",
                execute = function()
                    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
                    for k, v in unhidden_pairs(conditionsTable) do
                        if string.lower(v.name) == cond then
                            local riders = ability:GetRidersForCondition(k, casterToken, targetToken, options)
                            targetToken.properties:InflictCondition(k, {
                                duration = duration,
                                sourceDescription = string.format("Inflicted by %s's <b>%s</b> ability", creature.GetTokenDescription(casterToken), ability.name),
                                riders = riders,
                                casterInfo = {
                                    tokenid = casterToken.charid,
                                },
                                cast = options.symbols.cast,
                            })
                            break
                        end
                    end
                end,
            }
        end,
    }

end)


local function SubstituteGoblinScript(ability, casterToken, targetToken, options, rule)
    local match = regex.MatchGroups(rule, "(?<goblinscript>\\{[^\\}]*\\})", {indexes = true})
    if match ~= nil then
		local index = match.goblinscript.index
		local length = match.goblinscript.length

		local before = string.sub(rule, 1, index-1)
		local after = string.sub(rule, index+length)

        local goblinScript = string.sub(match.goblinscript.value, 2, #match.goblinscript.value - 1)

        local str = tostring(ExecuteGoblinScript(goblinScript, targetToken.properties:LookupSymbol(options.symbols), 0, "SubstituteGoblinScript"))

        rule = before .. str .. after


        return SubstituteGoblinScript(ability, casterToken, targetToken, options, rule)
    end

    return rule
end

function ActivatedAbilityDrawSteelCommandBehavior:ExecuteCommand(ability, casterToken, targetToken, options, rule)

    rule = SubstituteGoblinScript(ability, casterToken, targetToken, options, rule)

    self:ExecuteCommandInternal(ability, casterToken, targetToken, options, rule)

end

function ActivatedAbilityDrawSteelCommandBehavior:ExecuteCommandInternal(ability, casterToken, targetToken, options, rule)
    --print("Rule:: Executing:", rule)
    rule = string.lower(rule)
    if rule == "" then
        return
    end

    if targetToken == nil or not targetToken.valid then
        return
    end

    local targetImmuneToNonDamage = targetToken.properties:CalculateNamedCustomAttribute("Immune to Non Damage Effects") > 0
    --Allow for retargeting of damage only, all other effects ignored
    local newDamageTarget = options.symbols.cast:RedirectDamageTarget(targetToken)
    if newDamageTarget ~= nil then
        targetToken = newDamageTarget
        targetImmuneToNonDamage = true
    end
    --Check if the target previously have the damage only redirected
    --Set immune to non damage effects if so
    if options.symbols.cast then
        local retargets = options.symbols.cast:try_get("retargets", {})
        for _, entry in ipairs(retargets) do
            if entry.retargetType == "none" and entry.retargetid == targetToken.charid then
                targetImmuneToNonDamage = true
            end
        end
    end

    --print("Rule:: Before normalize:  " .. rule)
    rule = rule:gsub("<alpha=#00><alpha=#ff>.*", "")
    rule = regex.ReplaceAll(rule, "<[^<>]*?>", "")
    --print("Rule:: After normalize: " .. rule)

    rule = ActivatedAbilityDrawSteelCommandBehavior.NormalizeRuleTextForCreature(casterToken.properties, rule)

    local gateMatch = regex.MatchGroups(rule, "^(?<head>.*)(?<cond>(?<attr>[marip]) ?< ?\\[?(?<gate>-?[0-9]+|weak|average|strong)\\]?,? )(?<tail>.*)$")
    if gateMatch ~= nil then
        --see if the condition gate is exceeded.
        local gate
        if type(gateMatch.gate) == "string" then
            gate = casterToken.properties:CalculatePotencyValue(gateMatch.gate)
        else
            gate = tonumber(gateMatch.gate) + casterToken.properties:CalculateNamedCustomAttribute("Potency Bonus")
        end


        local attrid = GameSystem.AttributeByFirstLetter[string.lower(gateMatch.attr)] or "-"
        local result = (targetToken.properties:AttributeForPotencyResistance(attrid) or 0) >= gate
        print("GATE:: RESULT =", result, "from", targetToken.properties:AttributeForPotencyResistance(attrid) or 0, ">=", gate)
        if result then

            if options.powerRollPass == "target" then
                ability.RecordTokenMessage(targetToken, options, string.format("Resisted potency: %s(%d)<%d", string.upper(gateMatch.attr), targetToken.properties:AttributeForPotencyResistance(attrid) or 0, gate))
            end

            --resisted don't do the rest of it.
            rule = gateMatch.head
        else
            if options.powerRollPass == "target" then
                ability.RecordTokenMessage(targetToken, options, string.format("Did not resist potency: %s(%d)<%d", string.upper(gateMatch.attr), targetToken.properties:AttributeForPotencyResistance(attrid) or 0, gate))
            end
            --did not resist.
            rule = gateMatch.head .. gateMatch.tail
        end
    end

    local bestMatch = nil
    local bestMatchInfo = nil
    local rulesTable = dmhub.GetTable("importerPowerTableEffects")
    for _,pattern in unhidden_pairs(rulesTable) do
        local abilityMatch, matchInfo = pattern:MatchMCDMEffect(nil, ability.name, rule)
        if abilityMatch ~= nil then
            if matchInfo == nil then
                bestMatch = abilityMatch
                break
            end

            if bestMatchInfo == nil or matchInfo.all == nil or #matchInfo.all > #bestMatchInfo.all then
                bestMatch = abilityMatch
                bestMatchInfo = matchInfo
            end
        end
    end

    if bestMatch ~= nil then
        --print("Rule:: Matched standard effect:", bestMatch.name, "for", rule)
        for _,behavior in ipairs(bestMatch.behaviors) do
            if not behavior:IsFiltered(ability, casterToken, options) then
                if options.powerRollPass == nil or options.powerRollPass == "target" then
                    --TODO: see if power table effects should be able to have per-caster semantics?
                    behavior:Cast(ability, casterToken, behavior:ApplyToTargets(ability, casterToken, {{token = targetToken}}, options), options)
                    ability:CommitToPaying(casterToken, options)
                end

                if bestMatchInfo ~= nil then
                    local tail = string.sub(rule, #(bestMatchInfo.all or rule) + 1)
                    if tail ~= "" then
                        local matchBody = regex.MatchGroups(tail, "^ *[;,] *(?<body>.+)$")
                        if matchBody ~= nil then
                            tail = matchBody.body
                        end
                        self:ExecuteCommandInternal(ability, casterToken, targetToken, options, tail)
                    end
                end
            end
        end
        return
    end


    --print("Rule:: Trying to match rule: \"" .. rule .. "\"")
    for _,entry in ipairs(g_rulePatterns) do
        local patterns = entry.pattern
        if type(patterns) == "string" then
            patterns = {patterns}
        end
        for _,pattern in ipairs(patterns) do
            local match = regex.MatchGroups(rule, pattern)
            if match ~= nil and entry.validate ~= nil and not entry.validate(entry, match) then
                print("Rule:: pattern failed validation", entry.pattern)
                match = nil
            end

            if match ~= nil then
                if (not entry.isdamage) and targetImmuneToNonDamage then
                    print("Rule:: Target is immune to non-damage effects, skipping rule", entry.pattern)
                    return
                end

                local result = false
                if options.powerRollPass == nil or options.powerRollPass == (entry.pass or "target") then
                    result = entry.execute(self, ability, casterToken, targetToken, options, match)
                end
                print("Rule:: Execute pattern", entry.pattern)


                --a result of true means the rule is gated and we should stop processing.
                if result == true then
                    return
                end

                local tail = string.sub(rule, #(match.all or rule) + 1)

                print("Rule:: Matched \"" .. (match.all or rule) .. " against pattern \"" .. pattern .. "\". Tail: \"" .. tail .. "\"")

                rule = tail
                match = regex.MatchGroups(rule, "^( *, *| *and *| *then *| *; *)")

                if match == nil then
                    match = regex.MatchGroups(rule, "^ ")
                end

                if match ~= nil then
                    local orig = rule
                    rule = string.sub(rule, #(match.all or rule) + 1)

                    self:ExecuteCommandInternal(ability, casterToken, targetToken, options, rule)
                end

                return
            end
        end
    end

end

ActivatedAbilityTableRollBehavior.ExecuteCommand = ActivatedAbilityDrawSteelCommandBehavior.ExecuteCommand
ActivatedAbilityTableRollBehavior.ExecuteCommandInternal = ActivatedAbilityDrawSteelCommandBehavior.ExecuteCommandInternal

function ActivatedAbilityDrawSteelCommandBehavior.ValidateRule(rule)

    --print("Rule:: Validating rule(" .. rule .. ")")
    rule = string.lower(rule)
    if rule == "" then
        --print("Rule:: Returning true")
        return true
    end

    local AddGate = function(str)
        return str
    end
    local gateMatch = regex.MatchGroups(rule, "^(?<head>.*?)(?<gate>(<color=[^>]+>)?(<uppercase>)?[marip](</uppercase>)? ?< ?\\[?(-?[0-9]+|weak|average|strong)\\]?(</color>)?,? )(?<tail>.*)$")
    if gateMatch ~= nil then
        --print("Rule:: MATCHED GATE: head =", gateMatch.head, "tail =", gateMatch.tail, "gate =", gateMatch.gate)
        local startingRule = rule
        rule = gateMatch.head .. gateMatch.tail
        AddGate = function(str)
            if type(str) ~= "string" then
                return str
            end

            local insertIndex = #str - #gateMatch.tail

            if insertIndex <= 0 then
                return str
            end

            local result = str:sub(1,insertIndex) .. gateMatch.gate .. str:sub(insertIndex+1, -1)

            return result
        end
    else
        --print("Rule:: NO GATE MATCH")
    end

    local bestMatch = nil
    local bestMatchInfo = nil

    local rulesTable = dmhub.GetTable("importerPowerTableEffects")
    for _,pattern in unhidden_pairs(rulesTable) do
        local abilityMatch, matchInfo = pattern:MatchMCDMEffect(nil, "Ability", rule)
        if abilityMatch ~= nil then
            if matchInfo == nil then
                return true
            end

            if bestMatchInfo == nil or #matchInfo.all > #bestMatchInfo.all then
                bestMatch = abilityMatch
                bestMatchInfo = matchInfo
            end
        end
    end

    if bestMatchInfo ~= nil then
        if bestMatchInfo.all == nil or #bestMatchInfo.all >= #rule then
            --print("Rule:: Returning true")
            return true
        end

        local result = string.sub(rule, #bestMatchInfo.all + 1)
        --print("Rule:: validate matched pattern: (" .. bestMatchInfo.all .. "); rule = (" .. rule .. "); result = (" .. result .. ")")
        return AddGate(result)
    end

    --built in rule matches. Matched after we check compendium-defined patterns.
    for _,entry in ipairs(g_rulePatterns) do
        local patterns = entry.pattern
        if type(patterns) == "string" then
            patterns = {patterns}
        end
        for _,pattern in ipairs(patterns) do
            local match = regex.MatchGroups(rule, pattern)
            if match ~= nil then
                --print("Rule:: matched pattern", pattern)
            end

            if match ~= nil and entry.validate ~= nil and not entry.validate(entry, match) then
                --print("Rule:: validate failed")
                match = nil
            end

            if match ~= nil then
                local tail = string.sub(rule, #(match.all or rule) + 1)
                --print("Rule:: Validate Matched \"" .. (match.all or rule) .. "\" against pattern \"" .. pattern .. "\". Tail: \"" .. tail .. "\"")
                rule = tail
                match = regex.MatchGroups(rule, "^( *, *| *and *| *then *| *; *)")

                if match == nil then
                    match = regex.MatchGroups(rule, "^ ")
                end

                if match ~= nil then
                    rule = string.sub(rule, #match.all + 1)
                    --print("Rule:: pared down to (" .. rule .. ")")
                    local result = AddGate(ActivatedAbilityDrawSteelCommandBehavior.ValidateRule(rule))
                    return result
                elseif #trim(rule) > 1 then
                    return AddGate(rule)
                end

                return true
            end
        end
    end

    --print("Rule:: Returning (" .. rule .. ")")
    return AddGate(rule)
end


--- @param caster creature
--- @param rule string
--- @param notes {string}|nil
--- @return string
function ActivatedAbilityDrawSteelCommandBehavior.NormalizeDamageRuleTextForCreature(caster, rule, notes)
    local original = rule
    --search for something like 7 + M, A, or I damage
    local matchDamageWithCharacteristic = regex.MatchGroups(rule, "^(?<prefix>.*?)(?<number>[0-9]+)\\s*\\+\\s*(?<attr>[MARIPmarip, ]+,? or [MARIPmarip]+)(\\s*(?<suffix>.*)|(?<suffix>[;,].*))?$")
    if matchDamageWithCharacteristic == nil then
        --try to find with just a single attribute.
        matchDamageWithCharacteristic = regex.MatchGroups(rule, "^(?<prefix>.*?)(?<number>[0-9]+)\\s*\\+\\s*(?<attr>[MARIPmarip](?![A-Za-z]))(\\s*(?<suffix>.*)|(?<suffix>[;,].*))?$")
    end
    if matchDamageWithCharacteristic ~= nil then
        local baseDamage = tonumber(matchDamageWithCharacteristic.number)
        local attributes = regex.Split(matchDamageWithCharacteristic.attr, ", or |,| or ")
        local bonusDamage = nil
        local attributeUsed = nil
        for _,attrid in ipairs(attributes) do
            local attr = string.upper(string.trim(attrid))
            attr = GameSystem.AttributeByFirstLetter[string.lower(attr)] or "-"
            if attr ~= '-' then
                local newBonus = caster:AttributeMod(attr)
                if bonusDamage == nil or newBonus > bonusDamage then
                    bonusDamage = newBonus
                    attributeUsed = attr
                end
            end
        end

        if bonusDamage ~= nil then
            local totalDamage = baseDamage + bonusDamage

            if matchDamageWithCharacteristic.suffix ~= nil then
                rule = matchDamageWithCharacteristic.prefix .. tostring(totalDamage) .. " " .. matchDamageWithCharacteristic.suffix
            else
                rule = matchDamageWithCharacteristic.prefix .. tostring(totalDamage)
            end
            if notes ~= nil then
                local applicationDescription = ""
                if matchDamageWithCharacteristic ~= nil and string.find(matchDamageWithCharacteristic.suffix or "", "damage") then
                    applicationDescription = " in damage"
                end
                notes[#notes+1] = string.format("Caster's %s of %d included%s", creature.attributesInfo[attributeUsed].description, bonusDamage, applicationDescription)
            end
        end
    end

    return rule
end

--- @param caster creature
--- @param rule string
--- @param notes {string}|nil
--- @return string
function ActivatedAbilityDrawSteelCommandBehavior.NormalizeRuleTextForCreature(caster, rule, notes)
    local result = ActivatedAbilityDrawSteelCommandBehavior.NormalizeDamageRuleTextForCreature(caster, rule, notes)
    result = StringInterpolateGoblinScript(result, caster)
    return result
end

--@param caster: Creature|nil
--@param rule: string
--@param notes: {string}|nil
--@return string
function ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(caster, rule, notes, fullyImplemented)
    local starting = rule
    if caster ~= nil then
        local potencyStrong = caster:CalculatePotencyValue("Strong")
        local potencyAverage = caster:CalculatePotencyValue("Average")
        local potencyWeak = caster:CalculatePotencyValue("Weak")
        local startingRule = rule

        --old way. Deprecate later?
        rule = regex.ReplaceAll(rule, "(?<attr>[MARIP]) \\[weak\\]", string.format("<color=#ff4444><uppercase>${attr}</uppercase>%d</color>", potencyWeak))
        rule = regex.ReplaceAll(rule, "(?<attr>[MARIP]) \\[average\\]", string.format("<color=#ff4444><uppercase>${attr}</uppercase>%d</color>", potencyAverage))
        rule = regex.ReplaceAll(rule, "(?<attr>[MARIP]) \\[strong\\]", string.format("<color=#ff4444><uppercase>${attr}</uppercase>%d</color>", potencyStrong))

        --new way.
        rule = regex.ReplaceAll(rule, "(if the target has )?(?<attr>[MARIP]) < \\[?weak\\]?", string.format("<color=#ff4444><uppercase>${attr}</uppercase> < %d</color>", potencyWeak))
        rule = regex.ReplaceAll(rule, "(if the target has )?(?<attr>[MARIP]) < \\[?average\\]?", string.format("<color=#ff4444><uppercase>${attr}</uppercase> < %d</color>", potencyAverage))
        rule = regex.ReplaceAll(rule, "(if the target has )?(?<attr>[MARIP]) < \\[?strong\\]?", string.format("<color=#ff4444><uppercase>${attr}</uppercase> < %d</color>", potencyStrong))

        --Add potency bonus when numeric gate is used
        local potencyBonus = caster:CalculateNamedCustomAttribute("Potency Bonus")
        if starting == rule and potencyBonus > 0 then
            rule = string.gsub(rule, "([MARIPmarip])%s*<%s*(%-?%d+)", function(attr, gate)
                local adjustedGate = tonumber(gate) + potencyBonus
                return string.format("<color=#ff4444><uppercase>%s</uppercase> < %d</color>", string.upper(attr), adjustedGate)
            end)
        end

        if rule ~= startingRule and notes ~= nil then
            notes[#notes+1] = string.format("<color=#ff4444>Caster has a Potency of %d/%d/%d</color>", potencyWeak, potencyAverage, potencyStrong)
        end

        rule = ActivatedAbilityDrawSteelCommandBehavior.NormalizeRuleTextForCreature(caster, rule, notes)

    end

    --print("FullyImplemented::", rule, fullyImplemented)
    if not fullyImplemented then
        rule = ActivatedAbilityDrawSteelCommandBehavior.FormatRuleValidation(rule)
    else

        --make stop parsing after any #
        rule = string.gsub(rule, " #", " <alpha=#00><alpha=#ff>")
        if string.starts_with(rule, "#") then
            rule = "<alpha=#00><alpha=#ff>" .. string.sub(rule, 2)
        end
    end

    --print("Rule::", starting, "becomes", rule)

    return rule
end

function ActivatedAbilityDrawSteelCommandBehavior.FormatRuleValidation(rule)
    --print("Rule:: Validating (" .. rule .. ")")
    local text = ActivatedAbilityDrawSteelCommandBehavior.ValidateRule(rule)
    if type(text) == "string" then
        local before = string.sub(rule, 1, -#text - 1)

        --print("Rule:: rule = ", rule, "text = ", text, "before = ", before)
        text = text:gsub("<color=[^>]+>", "")
        text = text:gsub("</color>", "")

        local matchLiteral = regex.MatchGroups(text, "^[;,]?(?<whitespace>\\s*)#(?<text>.*)\\s*$")
        if matchLiteral ~= nil then
            print("Rule:: FORMAT ALPHA")
            --this alpha marks stop parsing rules.
            return string.format("%s<alpha=#00><alpha=#ff>%s%s", before, matchLiteral.whitespace, matchLiteral.text)
        end

        local result = string.format("%s<alpha=#55>%s", before, text)

       --print("Rule:: Validation: result = ", result)
        --print(string.format("Rule:: Validation: rule = (%s); text = (%s); before = (%s); result = (%s)", rule, text, before, result))
        return result
    else
        return rule
    end
end

function ActivatedAbilityDrawSteelCommandBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Rule:",
        },

        gui.Input{
            classes = "formInput",
            halign = "left",
            width = 320,
            fontSize = 14,
            placeholderText = "Enter Rule...",
            x = -10,
            text = self.rule,
            change = function(element)
                self.rule = element.text
                parentPanel:FireEvent("refreshBehavior")
            end,

        },
    }

    result[#result+1] = gui.Check{
        text = "Prompt When Resolving",
        value = self:try_get("promptWhenResolving", false),
        change = function(element)
            self.promptWhenResolving = element.value
            parentPanel:FireEvent("refreshBehavior")
        end,
    }

    if self:try_get("promptWhenResolving", false) then
        result[#result+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Prompt:",
            },
            gui.Input{
                classes = {"formInput"},
                text = self:try_get("promptWhenResolvingText", ""),
                placeholderText = "Choose Target",
                characterLimit = 240,
                change = function(element)
                    self.promptWhenResolvingText = element.text
                end
            }
        }
    end

	return result
end

Commands.download = function()
    local classes = dmhub.GetTable("classes")
    for k,v in pairs(classes) do
        if v.name == "Fury" then
            dmhub.DebugFileWriteObject("d:/dev/debug/class.json", v)
        end
    end
end

Commands.upload = function()
    local classes = dmhub.GetTable("classes")
    for k,v in pairs(classes) do
        if v.name == "Fury" then
            local obj = dmhub.DebugFileReadObject("d:/dev/debug/class.json")
            if obj ~= nil then
                dmhub.SetAndUploadTableItem("classes", obj)
                print("Uploaded")
                return
            else
                print("Object is null!")
            end
        end
    end

    print("Could not upload")
end