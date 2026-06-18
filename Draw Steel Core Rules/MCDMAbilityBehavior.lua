local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

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
    print("DSCommand:: Cast rule='" .. tostring(self.rule) .. "' targets=" .. tostring(#(targets or {})) .. " abort=" .. tostring(options.abort) .. " stopProcessing=" .. tostring(options.stopProcessing))
    local promptWhenResolving = self:try_get("promptWhenResolving", false)

    local targetChoices = {}
    if promptWhenResolving then
        for _,target in ipairs(targets or {}) do
            local targetToken = target.token
            targetChoices[#targetChoices+1] = targetToken
        end
    end

    ability:CommitToPaying(casterToken, options)

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

        --The prompt loop above can yield for a while; the caster may be deleted/
        --despawned in that window (token reference survives but .valid is false and
        --.properties is nil). The rule is evaluated against the caster's properties,
        --so a gone caster means there is nothing to evaluate or execute.
        if casterToken == nil or not casterToken.valid or casterToken.properties == nil then
            break
        end

        for _,target in ipairs(targets) do
            if target.token ~= nil then
                -- Expose Cast (with its memory), Target, Mode, etc. to GoblinScript
                -- in the rule string so authors can write damage formulas like
                -- {Min(1, Cast.Spaces Moved) * Might} damage or reference
                -- Cast.Memory("StartX") set by an earlier RememberBehavior.
                local ruleSymbols = table.shallow_copy(options.symbols or {})
                ruleSymbols.target = GenerateSymbols(target.token.properties)
                local rule = StringInterpolateGoblinScript(self.rule, casterToken.properties:LookupSymbol(ruleSymbols))
                --print("INTERPOLATE::", self.rule, "->", rule)
                self:ExecuteCommand(ability, casterToken, target.token, options, rule)
            end
        end
    until promptWhenResolving == false or targetChoices == nil or #targetChoices == 0
end

local function InvokeAbilityRemote(standardAbilityName, targetToken, casterToken, abilityAttr, options)

    local symbols = table.shallow_copy(options.symbols or {})

    --make sure symbols don't have any recursive symbols.
    symbols.cast = nil
    symbols.caster = nil
    symbols.target = nil
    symbols.targets = nil

    local invocation = AbilityInvocation.new{
        timestamp = ServerTimestamp(),
        userid = casterToken.activeControllerId,
        abilityType = "standard",
        standardAbility = standardAbilityName,
        targeting = "prompt",
        invokerid = casterToken.charid,
        casterid = targetToken.charid,
        symbols = symbols,
        abilityAttr = abilityAttr,
    }

    --local debugInfo = DebugCheckTableSelfReference(invocation)
    --if debugInfo then
    --    print("InvokeAbilityRemote:: Detected self reference in invocation table:", debugInfo)
    --    return
    --end

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
    local isRolledDamage = damage == nil

    --Patron damage handling (Acolyte class).
    --The literal token "patron" in tier/rule text is a placeholder for the
    --caster's patron-element damage type (corruption / holy / lightning).
    --Resolve here so the eventual damage event is typed correctly AND carries
    --the patrondamage flag for triggers and GoblinScript symbols.
    local patrondamage = false
    if damageType == "patron" then
        patrondamage = true
        local resolved = nil
        if casterToken ~= nil and casterToken.valid and casterToken.properties ~= nil
            and casterToken.properties.PatronDamageType ~= nil then
            resolved = casterToken.properties:PatronDamageType()
        end
        if type(resolved) == "string" and resolved ~= "" then
            damageType = string.lower(resolved)
        else
            damageType = "untyped"
            --One warning per cast: log to console (not chat) when a patron
            --damage tier fires from a caster with no patron set. options.symbols.cast
            --is the per-cast ActivatedAbilityCast; using a transient flag lets us
            --gate the warning per-cast without polluting persisted state.
            local cast = options ~= nil and options.symbols ~= nil and options.symbols.cast
            if cast == nil or not cast:try_get("_tmp_patronDamageWarned", false) then
                if cast ~= nil then cast._tmp_patronDamageWarned = true end
                print(string.format(
                    "PATRON DAMAGE:: caster '%s' has no patron_damage_type set; emitting untyped damage for tier text 'patron damage'.",
                    casterToken ~= nil and creature.GetTokenDescription(casterToken) or "?"
                ))
            end
        end
    end

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

    print("ExecuteDamage::", damage, damageType, "halfCount:", halfCount, "noDamage:", noDamage, "patron:", patrondamage)

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

        --Squad coordinated strike: attribute the damage to the MAIN minion for this
        --creature -- the first minion to target it -- so retaliation and "last
        --attacker" triggers point at that creature's main minion, not an arbitrary
        --attacker. (Same lookup the power-roll and invoke paths use.)
        local attacker = casterToken.properties
        if options.symbols.cast ~= nil then
            local attackerTok = options.symbols.cast:MainAttackerForTarget(options.symbols, targetToken, casterToken)
            if attackerTok ~= nil then
                attacker = attackerTok.properties
            end
        end

        if bonus ~= nil then
            damage = damage + bonus
        end

        --Snapshot before halving so the halved-away portion can be tracked as
        --damagePrevention. Taken after the characteristic bonus is added, so the
        --prevented amount is measured against the full pre-half damage.
        local damageBeforeHalving = damage

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
                    result = targetToken.properties:InflictDamageInstance(damage, damageType, ability.keywords, string.format("%s's %s", selfName, ability.name), { criticalhit = false, attacker = attacker, surges = options.surges, ability = ability, hasability = true, cast = options.symbols.cast, hasrolleddamage = isRolledDamage, patrondamage = patrondamage})
                    options.symbols.cast:CountDamage(targetToken, result.damageDealt, damage, isRolledDamage, patrondamage)

                    --Damage halved away by (half) power-roll modifiers counts as
                    --damagePrevention, credited to the target. The halving's true
                    --source (the target's own trait/trigger vs a protector ally)
                    --is not recoverable here -- the tier text only carries the
                    --bare "(half)" marker -- so the target is the best available
                    --attribution. TrackHeroStats self-guards, so monster targets
                    --are dropped.
                    if damage < damageBeforeHalving then
                        LiveEncounter.TrackHeroStats(targetToken.charid, "damagePrevention", damageBeforeHalving - damage)
                    end
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
        pattern = {"^(?<damage>[0-9 d+-]+)\\s*(?<type>[a-z]+)?\\s?damage(?<mods>(\\s*\\((?:half|no damage)\\))*)",
            "^(?<damage>[0-9]+)\\s+(?<type>[a-z]+)\\s+damage(?<mods>(\\s*\\((?:half|no damage)\\))*)",
            "^(?<damage>[0-9]+)\\s*\\+\\s*(?<bonus>[MARIPmarip, ]+ or [MARIPmarip]+)(\\s+(?<type>[a-z]+))?\\s*damage(?<mods>(\\s*\\((?:half|no damage)\\))*)",
            "^(?<damage>[0-9]+)\\s*\\+\\s*(?<bonus>[MARIPmarip])(?![a-z])(\\s+(?<type>[a-z]+))?\\s*damage(?<mods>(\\s*\\((?:half|no damage)\\))*)",
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
                --When a sub-ability's casterid has been remapped (e.g. Behold the Face of Justice), opt in via "forcemovefrominvoker" to use the original invoker as the pusher for the size check.
                local pusherToken = casterToken
                if ability:HasProperty("forcemovefrominvoker") then
                    local invoker = ability:try_get("invoker")
                    if invoker ~= nil then
                        local invokerToken = dmhub.LookupToken(invoker)
                        if invokerToken ~= nil and invokerToken.valid then
                            pusherToken = invokerToken
                        end
                    end
                end
                local casterSize = pusherToken.creatureSizeNumber
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
                    --Per-encounter hero stat: the hero's stability fully prevented
                    --the forced movement -- they stood firm. Runs once on the
                    --resolving client; TrackHeroStats self-guards to heroes.
                    LiveEncounter.TrackHeroStats(targetToken.charid, "standsFirm")
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
                forcedMovementThroughCreatures = ability:try_get("forcedMovementThroughCreatures", false),
                --This invoke relocates the TARGET (the pushed/pulled/slid creature),
                --which becomes the caster of the forced-movement clone. InvokeAbility
                --copies the parent ability's keywords onto the clone, so a forced
                --movement from a Strike (e.g. Null's Magnetic Strike) carries the
                --"Strike" keyword. If the target is a minion in a squad, that makes
                --UsesSquadCoordination/UsesSquadStrike fire on the relocate clone and
                --GetNumTargets multiply by the squad's minion count -- so the action
                --bar waits for N target spaces and the destination click never
                --confirms the pull. Forced movement is always per-target, never a
                --squad-coordinated action, so opt out explicitly.
                disableSquadCoordination = true,
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
                        casterToken.properties.moveDistanceRoundId = dmhub.initiativeQueue:GetTurnId()
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
                                local casterClassInfo = casterToken.properties:IsHero() and casterToken.properties:GetClass() or nil
                                local targetClassInfo = targetToken.properties:IsHero() and targetToken.properties:GetClass() or nil
                                track("condition_apply", {
                                    condition = k,
                                    sourceAbility = ability.name,
                                    sourceCaster = casterClassInfo and casterClassInfo.name or casterToken.properties:try_get("monster_type", "monster"),
                                    target = targetClassInfo and targetClassInfo.name or targetToken.properties:try_get("monster_type", "monster"),
                                    targetIsHero = targetToken.properties:IsHero(),
                                    stacks = 1,
                                    dailyLimit = 50,
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
    -- NOTE: "Gain N <heroic resource>" is handled dynamically by the
    -- refreshTables handler below (see g_gainHeroicResourceIndex). The set of
    -- heroic-resource names is built by scanning the classes table so that
    -- custom (user-authored) classes are recognized too, rather than relying
    -- on a hard-coded list of the standard class resources.
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
        -- Apply the Invisible From condition to the caster (the ability user),
        -- with the ability's TARGET stored as the condition's caster. Used by
        -- the Sporeling's Spore Puff: "the sporeling is invisible to the target
        -- until the end of the sporeling's next turn". Because the condition
        -- lives on the sporeling, `end_of_next_turn` lines up with the
        -- sporeling's turn (not the target's), and the Invisible From modifier
        -- reads `ConditionCaster("Invisible From")` to identify the attacker
        -- whose strikes should take a bane.
        pass = "caster",
        pattern = "^become invisible from target \\((?<duration>eot|eoe|save ends)\\)",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            local duration = string.lower(match.duration)
            if string.starts_with(duration, "save") then
                duration = "save"
            end

            local invisibleFromId = "9d4f1c95-5c2b-4a76-b428-3e4f1d2c8a05"
            casterToken:ModifyProperties{
                description = "Apply Invisible From",
                execute = function()
                    casterToken.properties:InflictCondition(invisibleFromId, {
                        duration = duration,
                        sourceDescription = string.format("Inflicted by %s's <b>%s</b> ability", creature.GetTokenDescription(casterToken), ability.name),
                        casterInfo = {
                            tokenid = targetToken.charid,
                        },
                        cast = options.symbols.cast,
                    })
                end,
            }
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
    },

    {
        pattern = "^free strike or grabbed if adjacent$",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            -- Check if target ended up adjacent after being pulled
            local distance = casterToken:Distance(targetToken)
            print("FreeStrikeOrGrab:: distance=" .. tostring(distance) .. " caster=" .. creature.GetTokenDescription(casterToken) .. " target=" .. creature.GetTokenDescription(targetToken))
            if distance > 1 then
                print("FreeStrikeOrGrab:: target not adjacent (distance > 1), skipping")
                return
            end

            ability:CommitToPaying(casterToken, options)

            -- Try to invoke a free strike (skippable). If skipped, grab instead.
            local freeStrikeAbility = MCDMUtils.GetStandardAbility("Melee Free Strike")
            print("FreeStrikeOrGrab:: standard ability found=" .. tostring(freeStrikeAbility ~= nil) .. " freeStrikeDmg=" .. tostring(casterToken.properties:OpportunityAttack()))
            local madeStrike = false
            if freeStrikeAbility ~= nil then
                local abilityClone = DeepCopy(freeStrikeAbility)
                abilityClone.skippable = true
                abilityClone.notooltip = true
                abilityClone.keywords = ability.keywords
                abilityClone.recordTargets = true
                abilityClone.promptOverride = "Target pulled adjacent! Make a free strike? (Skip to grab instead)"

                -- Set up the free strike damage from the caster's free strike value
                local freeStrikeDamage = tostring(casterToken.properties:OpportunityAttack())
                abilityClone.behaviors[1].roll = freeStrikeDamage .. "*Charges"

                local symbols = {
                    invoker = GenerateSymbols(casterToken.properties),
                    cast = options.symbols.cast,
                    charges = options.symbols.charges,
                }

                madeStrike = ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(
                    casterToken,    -- invokerToken
                    abilityClone,   -- ability
                    casterToken,    -- casterToken (monster makes the free strike)
                    "prompt",       -- targeting
                    symbols,
                    options
                )
                print("FreeStrikeOrGrab:: ExecuteInvoke returned madeStrike=" .. tostring(madeStrike))
            else
                print("FreeStrikeOrGrab:: Melee Free Strike standard ability not found!")
            end

            if not madeStrike then
                -- Controller skipped free strike (or no free strike available) -> apply Grabbed
                local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
                for k,v in unhidden_pairs(conditionsTable) do
                    if string.lower(v.name) == "grabbed" then
                        ability.RecordTokenMessage(targetToken, options, "Grabbed")
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
                            end,
                        }
                        break
                    end
                end
            end
        end,
    },
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

        local recipientToken = targetToken
        local summonerToken = targetToken.properties:GetSurgeSharingSummonerToken()
        if summonerToken ~= nil then
            recipientToken = summonerToken
        end

        recipientToken:ModifyProperties{
            description = "Gain Surges",
            execute = function()
                recipientToken.properties:RefreshResource(CharacterResource.surgeResourceId, "unbounded", quantity, string.format("%s used %s", casterToken.name, ability.name))
            end,
        }
    end,
}

local g_gainResourceIndex = nil
local g_applyConditionIndex = nil
local g_gainConditionWithRiderIndex = nil
local g_gainHeroicResourceIndex = nil
local g_gainConditionByNameWithRiderIndex = nil

-- A condition rider rides along on its host condition, so its duration always
-- matches the condition's. When a rider rule supplies an explicit
-- (eot|eoe|save ends) duration we honor it; otherwise we inherit the host
-- condition's current duration. Conditions like Grabbed and Prone have no fixed
-- duration (nil), so in those cases the rider simply stays active for as long
-- as the host condition is active.
local function ResolveRiderDuration(matchDuration, targetToken, conditionid)
    if matchDuration ~= nil and matchDuration ~= "" then
        local duration = string.lower(matchDuration)
        if string.starts_with(duration, "save") then
            duration = "save"
        end
        return duration
    end

    local inflicted = targetToken.properties:try_get("inflictedConditions")
    if inflicted ~= nil and inflicted[conditionid] ~= nil then
        return inflicted[conditionid].duration
    end

    return nil
end

dmhub.RegisterEventHandler("refreshTables", function(keys)
    if mod.unloaded then
        return
    end

	if keys ~= nil and (not keys[CharacterResource.tableName]) and (not keys[Class.tableName]) and (not keys[CharacterCondition.tableName]) and (not keys[CharacterCondition.ridersTableName]) then
		return
	end


    -- Pattern: "Weakened Tail Spike (Save Ends)" -- condition name + rider powerTableText + duration.
    -- The duration is optional: a rider with no explicit duration (e.g. "Grabbed and
    -- Roughed Up") inherits the host condition's duration. When omitted, the rider name
    -- must be followed by end-of-rule or a connector so a shorter rider name cannot match
    -- as a prefix of a longer one.
    g_gainConditionByNameWithRiderIndex = g_gainConditionByNameWithRiderIndex or #g_rulePatterns + 1
    g_rulePatterns[g_gainConditionByNameWithRiderIndex] = {
        pattern = "^(?<condition>" .. GetTableNameRegex(CharacterCondition.tableName, "powertable") .. ") (?<rider>" .. GetTableNameRegex(CharacterCondition.ridersTableName, nil, "powerTableText") .. ")(?:\\s+\\((?<duration>eot|eoe|save ends)\\)|(?=$|\\s*[,;]|\\s+and\\b|\\s+then\\b))",
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            local condName = match.condition
            local riderName = match.rider

            local conditionid = nil
            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            for k, v in unhidden_pairs(conditionsTable) do
                local vname = regex.ReplaceAll(string.lower(v.name), "[^a-z0-9 ]", "")
                if vname == condName then
                    conditionid = k
                    break
                end
            end

            if conditionid == nil then
                print("Rider:: Could not find condition for '" .. condName .. "'")
                return
            end

            local riderid = nil
            local t = dmhub.GetTable(CharacterCondition.ridersTableName)
            for key, value in unhidden_pairs(t) do
                local name = regex.ReplaceAll(string.lower(value["powerTableText"]), "[^a-z0-9 ]", "")
                if name == string.lower(riderName) then
                    riderid = key
                    break
                end
            end

            if riderid == nil then
                print("Rider:: Could not find rider for '" .. riderName .. "'")
                return
            end

            local duration = ResolveRiderDuration(match.duration, targetToken, conditionid)

            targetToken:ModifyProperties {
                description = "Inflict Condition",
                execute = function()
                    targetToken.properties:InflictCondition(conditionid, {
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

    -- Pattern: "Roughed Up (EoT)" -- bare rider powerTableText + optional duration. A rider
    -- with no explicit duration (e.g. "and Roughed Up") inherits the duration of its host
    -- condition. When omitted, the rider name must be followed by end-of-rule or a connector
    -- so a shorter rider name cannot match as a prefix of a longer one.
    g_gainConditionWithRiderIndex = g_gainConditionWithRiderIndex or #g_rulePatterns + 1
    g_rulePatterns[g_gainConditionWithRiderIndex] = {
        pattern = "^(?<rider>" .. GetTableNameRegex(CharacterCondition.ridersTableName, nil, "powerTableText") .. ")(?:\\s+\\((?<duration>eot|eoe|save ends)\\)|(?=$|\\s*[,;]|\\s+and\\b|\\s+then\\b))",
        execute = function(behavior, ability, casterToken, targetToken, options, match)

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

            local duration = ResolveRiderDuration(match.duration, targetToken, riderInfo.condition)

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
        -- The "(duration)" suffix is optional. A bare condition name with no
        -- parenthetical is only accepted for indefinite-duration conditions
        -- (e.g. "Grabbed"), enforced by validate below; conditions that need a
        -- duration must still carry a "(eot)" / "(save ends)" / "(eoe)" suffix.
        pattern = "^(?<condition>" .. GetTableNameRegex(CharacterCondition.tableName, "powertable") .. ")(?<parens> \\((?<duration>eot|EoT|save ends|eoe)?\\))?",
        validate = function(entry, match)
            -- A parenthetical was present (even an empty "()"): always allow,
            -- preserving the prior behavior where parens were mandatory.
            if match.parens ~= nil and match.parens ~= "" then
                return true
            end

            -- Bare name with no parens: only valid for an indefinite-duration
            -- condition. Otherwise reject so a more specific rule (or none) is
            -- used, matching the old behavior where bare names did not apply.
            local cond = match.condition
            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            for _, v in unhidden_pairs(conditionsTable) do
                if string.lower(v.name) == cond then
                    return v.indefiniteDuration == true
                end
            end
            return false
        end,
        execute = function(behavior, ability, casterToken, targetToken, options, match)
            ability:CommitToPaying(casterToken, options)
            local duration = string.lower(match.duration or "")
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
                            -- Indefinite-duration conditions ignore any typed
                            -- duration and apply with no set duration (eoe),
                            -- matching the manual "Add Condition" menu.
                            local appliedDuration = duration
                            if v.indefiniteDuration then
                                appliedDuration = "eoe"
                            end
                            local riders = ability:GetRidersForCondition(k, casterToken, targetToken, options)
                            targetToken.properties:InflictCondition(k, {
                                duration = appliedDuration,
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

    -- Build the "Gain N <heroic resource>" pattern dynamically by scanning the
    -- classes table for the heroic-resource name each class uses. This way the
    -- pattern recognizes user-authored custom classes, not just the standard
    -- ones. Regardless of which name matched, the caster's heroic resource
    -- (CharacterResource.heroicResourceId) is the resource that is refreshed.
    g_gainHeroicResourceIndex = g_gainHeroicResourceIndex or #g_rulePatterns + 1

    local heroicResourceNames = {}
    local seenHeroicResourceNames = {}
    for _,classInfo in pairs(dmhub.GetTable(Class.tableName) or {}) do
        if not classInfo:try_get("hidden", false) then
            local name = regex.ReplaceAll(string.lower(classInfo.heroicResourceName or ""), "[^a-z0-9 ]", "")
            name = trim(name)
            if name ~= "" and not seenHeroicResourceNames[name] then
                seenHeroicResourceNames[name] = true
                heroicResourceNames[#heroicResourceNames+1] = name
            end
        end
    end

    if #heroicResourceNames > 0 then
        g_rulePatterns[g_gainHeroicResourceIndex] = {
            pattern = "^[Gg]ain +(?<amount>[0-9]+) +(?<resource>" .. table.concat(heroicResourceNames, "|") .. ")",
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
        }
    end

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
    --Mirror the name normalization done by GetTableNameRegex, which strips
    --apostrophes from condition/rider names when building the match patterns
    --(e.g. "Let's Tussle" becomes "lets tussle"). The rule text must be stripped
    --the same way or a rider whose name contains an apostrophe never matches.
    --Apostrophes carry no structural meaning in rule text (no duration/gate/
    --damage syntax uses one), so removing them is safe.
    rule = rule:gsub("'", "")
    --print("Rule:: After normalize: " .. rule)

    rule = ActivatedAbilityDrawSteelCommandBehavior.NormalizeRuleTextForCreature(casterToken.properties, rule)

    local gateMatch = regex.MatchGroups(rule, "^(?<head>.*)(?<cond>(?<attr>[marip]) ?< ?\\[?(?<gate>-?[0-9]+|weak|average|strong)\\]?,? )(?<tail>[^;]*)(?<rest>;.*)?$")
    if gateMatch ~= nil then
        --see if the condition gate is exceeded.
        local gate
        if type(gateMatch.gate) == "string" then
            gate = casterToken.properties:CalculatePotencyValue(gateMatch.gate)
        else
            gate = tonumber(gateMatch.gate) + casterToken.properties:CalculateNamedCustomAttribute("Potency Bonus") + casterToken.properties:ScaledPotencyGateBonus()
        end


        local attrid = GameSystem.AttributeByFirstLetter[string.lower(gateMatch.attr)] or "-"
        local resistanceValue = targetToken.properties:AttributeForPotencyResistance(attrid) or 0

        -- Apply resistance modification formulas from active modifiers on caster and target
        local resistanceSources = {
            {creature = casterToken.properties, rollType = "ability_power_roll"},
            {creature = targetToken.properties, rollType = "enemy_ability_power_roll"},
        }
        local filterOptions = {ability = ability, caster = casterToken.properties, target = targetToken.properties}
        for _, source in ipairs(resistanceSources) do
            for _, mod in ipairs(source.creature:GetActiveModifiers()) do
                local rf = mod.mod:try_get("resistanceFormula", "")
                if rf ~= "" then
                    local desc = mod.mod:DescribeModifyPowerRoll(mod, source.creature, source.rollType, filterOptions)
                    if desc ~= nil then
                        local hint = mod.mod:HintModifyPowerRolls(mod, source.creature, source.rollType, filterOptions)
                        if hint ~= nil and hint.result then
                            local resistanceLookup = targetToken.properties:LookupSymbol({
                                resistance = resistanceValue,
                                caster = GenerateSymbols(casterToken.properties),
                            })
                            local newValue = ExecuteGoblinScript(rf, resistanceLookup, resistanceValue, "Resistance Modifier")
                            if newValue ~= nil then
                                resistanceValue = newValue
                            end
                        end
                    end
                end
            end
        end

        local result = resistanceValue >= gate
        if result then

            if options.powerRollPass == "target" then
                ability.RecordTokenMessage(targetToken, options, string.format("Resisted potency: %s(%d)<%d", string.upper(gateMatch.attr), resistanceValue, gate))
            end

            --resisted don't do the gated part, but keep anything after the semicolon.
            rule = gateMatch.head .. (gateMatch.rest or "")
        else
            if options.powerRollPass == "target" then
                ability.RecordTokenMessage(targetToken, options, string.format("Did not resist potency: %s(%d)<%d", string.upper(gateMatch.attr), resistanceValue, gate))
            end
            --did not resist.
            rule = gateMatch.head .. gateMatch.tail .. (gateMatch.rest or "")
        end
    end

    -- Clean up duplicate semicolons and leading semicolons left after gate removal
    rule = rule:gsub(";%s*;", ";")
    rule = rule:gsub("^%s*;%s*", "")

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

--- @class ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior:ActivatedAbilityBehavior
--- Runs as the final step of a free strike. Walks the caster's active power-roll
--- modifiers, picks any flagged with applyToFreeStrikes=true and a non-empty
--- addText, evaluates their activationCondition + keyword filters against the
--- free-strike ability+target, and applies each surviving addText as a Power
--- Table Effect (same engine path as ActivatedAbilityDrawSteelCommandBehavior's
--- rule). This bridges the gap that free strikes resolve as flat damage and
--- never enter the power-roll modifier pipeline.
ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior = RegisterGameType("ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior.summary = 'Apply Flagged Power Modifiers (Free Strike)'

ActivatedAbility.RegisterType
{
    id = 'apply_free_strike_power_modifiers',
    text = 'Apply Flagged Power Modifiers (Free Strike)',
    hidden = true, --internal: not exposed in the user-facing behavior picker.
    createBehavior = function()
        return ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior.new{
        }
    end
}

function ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Apply Flagged Power Modifiers (Free Strike)"
end

function ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior:Cast(ability, casterToken, targets, options)
    if casterToken == nil or not casterToken.valid then
        return
    end
    if casterToken.properties == nil then
        return
    end
    if targets == nil or #targets == 0 then
        return
    end

    --commandHelper is the Lua "self" we'll borrow from to invoke
    --ExecuteCommand. ExecuteCommand only reads its rule argument and self's
    --type info, so a transient instance is fine.
    local commandHelper = ActivatedAbilityDrawSteelCommandBehavior.new{}

    local activeModifiers = casterToken.properties:GetActiveModifiers()
    for _,modEntry in ipairs(activeModifiers) do
        local modifier = modEntry.mod
        if modifier ~= nil and modifier.behavior == "power" and modifier:try_get("applyToFreeStrikes", false) then
            local addText = trim(modifier:try_get("addText", ""))
            if addText ~= "" then
                --Apply the same keyword filter the standard power-modifier
                --pipeline uses (see hintPowerRoll). matchAnyKeywords semantics
                --are preserved. rollType == "all" intentionally skips this in
                --the standard pipeline; replicate that.
                local keywordsOk = true
                local keywords = modifier:try_get("keywords")
                if keywords ~= nil and modifier:try_get("rollType", "ability_power_roll") ~= "all" then
                    local totalCount = 0
                    local matchCount = 0
                    for keyword,_ in pairs(keywords) do
                        if keyword ~= "_luaTable" then
                            totalCount = totalCount + 1
                            if ability:HasKeyword(keyword) then
                                matchCount = matchCount + 1
                            end
                        end
                    end
                    if totalCount > 0 and matchCount < totalCount and (matchCount == 0 or not modifier:try_get("matchAnyKeywords", false)) then
                        keywordsOk = false
                    end
                end

                if keywordsOk and modifier:PassesFilter(casterToken.properties) then
                    --Activation condition: matches the symbol shape used by
                    --power.hintPowerRoll so authors can keep one expression
                    --(Self.X / Caster.X / Target.X / Ability.X) consistent
                    --across the full-ability path and the free-strike path.
                    local activationOk = true
                    local activationCondition = modifier:try_get("activationCondition", true)
                    if activationCondition == false then
                        activationOk = false
                    elseif activationCondition ~= true then
                        local firstTarget = (targets[1] and targets[1].token) or nil
                        local firstTargetProps = (firstTarget ~= nil and firstTarget.valid) and firstTarget.properties or nil
                        local lookupFunction = casterToken.properties:LookupSymbol(modifier:AppendSymbols{
                            ability = GenerateSymbols(ability),
                            target = GenerateSymbols(firstTargetProps),
                            caster = GenerateSymbols(casterToken.properties),
                            self = GenerateSymbols(casterToken.properties),
                            cast = options.symbols and options.symbols.cast,
                            title = "",
                        })
                        activationOk = GoblinScriptTrue(ExecuteGoblinScript(activationCondition, lookupFunction, 0, "Free Strike Power Modifier Activation Condition"))
                    end

                    if activationOk then
                        --Apply per-target: interpolate addText with the
                        --target installed as a symbol so Target.X formulas
                        --resolve correctly, then dispatch via the same
                        --ExecuteCommand path "Power Table Effect" rules use.
                        for _,target in ipairs(targets) do
                            local targetToken = target.token
                            if targetToken ~= nil and targetToken.valid then
                                local ruleSymbols = table.shallow_copy(options.symbols or {})
                                ruleSymbols.target = GenerateSymbols(targetToken.properties)
                                ruleSymbols.caster = GenerateSymbols(casterToken.properties)
                                ruleSymbols.self = GenerateSymbols(casterToken.properties)
                                ruleSymbols.ability = GenerateSymbols(ability)
                                local lookupFunction2 = casterToken.properties:LookupSymbol(modifier:AppendSymbols(ruleSymbols))
                                local interpolated = StringInterpolateGoblinScript(addText, lookupFunction2)
                                if interpolated ~= nil and trim(interpolated) ~= "" then
                                    print("FreeStrikeMods:: applying '" .. tostring(interpolated) .. "' from modifier '" .. tostring(modifier:try_get("name", "?")) .. "' to " .. creature.GetTokenDescription(targetToken))
                                    commandHelper:ExecuteCommand(ability, casterToken, targetToken, options, interpolated)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior.AppendToFreeStrike(freeStrikeAbility)
    if freeStrikeAbility == nil or freeStrikeAbility.behaviors == nil then
        return
    end
    --Guard against double-add if a caller invokes this twice on the same clone.
    for _,b in ipairs(freeStrikeAbility.behaviors) do
        if b.typeName == "ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior" then
            return
        end
    end
    freeStrikeAbility.behaviors[#freeStrikeAbility.behaviors+1] = ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior.new{}
end

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
    local gateMatch = regex.MatchGroups(rule, "^(?<head>.*?)(?<gate>(<color=[^>]+>)?(<uppercase>)?[marip](</uppercase>)? ?< ?\\[?(-?[0-9]+|weak|average|strong)\\]?(</color>)?,? )(?<tail>[^;]*)(?<rest>;.*)?$")
    if gateMatch ~= nil then
        --print("Rule:: MATCHED GATE: head =", gateMatch.head, "tail =", gateMatch.tail, "gate =", gateMatch.gate)
        local startingRule = rule
        rule = gateMatch.head .. gateMatch.tail .. (gateMatch.rest or "")
        AddGate = function(str)
            if type(str) ~= "string" then
                return str
            end

            local insertIndex = #str - #gateMatch.tail - #(gateMatch.rest or "")

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
        --Mirror runtime ExecuteCommandInternal: optionally strip a leading separator and revalidate
        --the tail so subsequent clauses don't show grey when they actually fire at runtime.
        local matchBody = regex.MatchGroups(result, "^ *[;,] *(?<body>.+)$")
        if matchBody ~= nil then
            result = matchBody.body
        end
        return AddGate(ActivatedAbilityDrawSteelCommandBehavior.ValidateRule(result))
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

        --Add potency bonus (plus any level-scaling literal-gate shift) when a
        --numeric gate is used. The ~= 0 guard (was > 0) lets a negative shift --
        --i.e. scaling a monster DOWN -- rewrite the gate too, matching what the
        --resolution save-check already does, so the shown gate never disagrees
        --with the actual save.
        local potencyBonus = caster:CalculateNamedCustomAttribute("Potency Bonus") + caster:ScaledPotencyGateBonus()
        if starting == rule and potencyBonus ~= 0 then
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
        -- Use original-case suffix for display; text (lowercased) is only used for structural matching below.
        local displayText = string.sub(rule, #before + 1)
        text = text:gsub("<color=[^>]+>", "")
        text = text:gsub("</color>", "")

        local matchLiteral = regex.MatchGroups(text, "^[;,]?(?<whitespace>\\s*)#(?<text>.*)\\s*$")
        if matchLiteral ~= nil then
            print("Rule:: FORMAT ALPHA")
            --this alpha marks stop parsing rules.
            local origMatchLiteral = regex.MatchGroups(displayText, "^[;,]?(?<whitespace>\\s*)#(?<text>.*)\\s*$")
            if origMatchLiteral ~= nil then
                return string.format("%s<alpha=#00><alpha=#ff>%s%s", before, origMatchLiteral.whitespace, origMatchLiteral.text)
            end
            return string.format("%s<alpha=#00><alpha=#ff>%s%s", before, matchLiteral.whitespace, matchLiteral.text)
        end

        --Dim non-rule (unvalidated) text so it reads as "not recognized as a
        --rule" without becoming illegible. #99 is ~60% alpha; #55 (~33%) washed
        --out badly on light themed fills (e.g. the accent-gold power-roll rows).
        local result = string.format("%s<alpha=#99>%s", before, displayText)

       --print("Rule:: Validation: result = ", result)
        --print(string.format("Rule:: Validation: rule = (%s); text = (%s); before = (%s); result = (%s)", rule, text, before, result))
        return result
    else
        return rule
    end
end

----------------------------------------------------------------
-- Diagnostician: vocabulary cache + compendium suppression set
----------------------------------------------------------------
-- Editor-only support for the power roll preview's chip strip.
-- The chip strip tells authors WHY a clause didn't parse (typo,
-- missing duration, unknown damage type, unrecognized segment)
-- rather than only colouring white-vs-grey. The vocab built here
-- is the lookup table that powers near-miss matching and the
-- compendium-pattern suppression that keeps prose-shaped tokens
-- the importer already knows about quiet.
--
-- Built lazily; cache invalidates on refreshTables and rebuilds
-- on next read. Mirrors the g_tierTextCache pattern used by the
-- power roll renderer.

-- English connectives, modals, and number words that show up in
-- pattern strings but should never be did-you-mean targets or
-- suppression keywords. They'd produce nonsense suggestions
-- (e.g. "thr" -> "the") and don't carry mechanical meaning.
local g_diagnosticStopwords = {
    ["a"] = true, ["an"] = true, ["the"] = true, ["and"] = true,
    ["or"] = true, ["of"] = true, ["to"] = true, ["in"] = true,
    ["is"] = true, ["are"] = true, ["be"] = true, ["by"] = true,
    ["on"] = true, ["at"] = true, ["as"] = true, ["do"] = true,
    ["if"] = true, ["it"] = true, ["its"] = true, ["new"] = true,
    ["up"] = true, ["has"] = true, ["have"] = true, ["had"] = true,
    ["was"] = true, ["were"] = true, ["been"] = true, ["being"] = true,
    ["can"] = true, ["could"] = true, ["should"] = true, ["would"] = true,
    ["may"] = true, ["might"] = true, ["must"] = true, ["will"] = true,
    ["into"] = true, ["onto"] = true, ["out"] = true, ["off"] = true,
    ["you"] = true, ["your"] = true, ["yours"] = true,
    ["with"] = true, ["from"] = true, ["for"] = true,
    ["all"] = true, ["any"] = true, ["but"] = true, ["not"] = true,
    ["each"] = true, ["this"] = true, ["that"] = true, ["these"] = true,
    ["those"] = true, ["them"] = true, ["they"] = true, ["their"] = true,
    ["one"] = true, ["two"] = true, ["three"] = true, ["four"] = true,
    ["five"] = true, ["six"] = true, ["seven"] = true, ["eight"] = true,
    ["nine"] = true, ["ten"] = true,
    -- Additional common English words that surfaced as Kind 1 false
    -- positives during the Silver+ compendium sweep. Most are
    -- modals, pronouns, or quantifiers that share short edit
    -- distance with mechanical vocab (e.g. "can" -> "cant",
    -- "other" -> "another", "whose" -> "choose").
    ["can"] = true, ["cant"] = true,
    ["other"] = true, ["others"] = true,
    ["whose"] = true, ["whom"] = true, ["who"] = true,
    ["which"] = true, ["whether"] = true,
    ["both"] = true, ["either"] = true, ["neither"] = true,
    ["some"] = true, ["many"] = true, ["most"] = true, ["least"] = true,
    ["more"] = true, ["less"] = true, ["also"] = true, ["just"] = true,
    ["only"] = true, ["even"] = true, ["very"] = true, ["yet"] = true,
    ["already"] = true, ["again"] = true, ["still"] = true,
    ["here"] = true, ["there"] = true, ["where"] = true, ["when"] = true,
    ["how"] = true, ["why"] = true, ["what"] = true,
    ["per"] = true, ["because"] = true, ["since"] = true, ["while"] = true,
    ["after"] = true, ["before"] = true, ["above"] = true, ["below"] = true,
    ["between"] = true, ["among"] = true, ["near"] = true, ["far"] = true,
    ["does"] = true, ["did"] = true, ["doing"] = true, ["done"] = true,
    ["make"] = true, ["made"] = true, ["makes"] = true, ["making"] = true,
    ["take"] = true, ["takes"] = true, ["taken"] = true, ["taking"] = true,
    ["see"] = true, ["seen"] = true, ["sees"] = true, ["saw"] = true,
    ["get"] = true, ["gets"] = true, ["got"] = true, ["gotten"] = true,
    ["use"] = true, ["uses"] = true, ["used"] = true, ["using"] = true,
}

-- Pull alphabetic word runs out of a regex pattern string. Strips
-- regex syntax (group names, character classes, escapes) and keeps
-- only lowercase ASCII letter runs that are not stopwords. Length
-- floor of 3 lets through short mechanical tokens like "eot"
-- without dragging in two-letter connectives.
--
-- We also strip letters trailing a character class because patterns
-- like "[Gg]ain" or "[MARIPmarip]+" represent a single
-- case-insensitive match plus its spelling tail; extracting the
-- bare tail ("ain", "marip") would produce nonsense vocab.
local function ExtractDiagnosticWordsFromPattern(pattern, sink)
    if type(pattern) ~= "string" then
        return
    end
    local cleaned = pattern
    cleaned = cleaned:gsub("%(%?<[^>]+>", "(") -- named-group identifiers
    cleaned = cleaned:gsub("%b[][%a]*", " ")   -- char classes + spelling tail
    cleaned = cleaned:gsub("\\%a", " ")        -- escape sequences (\s \d ...)
    cleaned = string.lower(cleaned)
    for word in cleaned:gmatch("[a-z]+") do
        if #word >= 3 and not g_diagnosticStopwords[word] then
            sink[word] = true
        end
    end
end

local g_diagnosticVocabCache = nil
local g_diagnosticCompendiumKeywordCache = nil

local function BuildDiagnosticVocab()
    local vocab = {
        damageTypes = {},
        conditions = {},
        riderNames = {},
        keywords = {},          -- built-in g_rulePatterns keywords
        importerKeywords = {},  -- importerPowerTableEffects keywords
        searchTokens = {},
    }

    local seen = {}

    local addToken = function(word, kind)
        if word == nil or word == "" then return end
        word = string.lower(word)
        if g_diagnosticStopwords[word] then return end
        if #word < 3 then return end
        local existingKind = seen[word]
        if existingKind ~= nil then
            -- Prefer the more specific kind (damageType > condition > rider > keyword)
            -- so the chip phrasing matches the most useful category.
            return
        end
        seen[word] = kind
        vocab.searchTokens[#vocab.searchTokens+1] = {word = word, kind = kind}
    end

    -- 1. Damage types from the rules table (populated by DamageTypes.lua
    --    on refreshTables). Falls back gracefully if not yet built.
    local damageTypeList = rules and rules.damageTypesAvailable or nil
    if type(damageTypeList) == "table" then
        for _,name in ipairs(damageTypeList) do
            local n = string.lower(name)
            vocab.damageTypes[n] = true
            addToken(n, "damageType")
        end
    end

    -- 2. Conditions: every entry in the conditions table, keyed by
    --    its lowercased display name. We capture indefiniteDuration
    --    so Kind 2 (missing duration) can skip prone/grabbed/etc.
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
    for _,entry in unhidden_pairs(conditionsTable) do
        local n = string.lower(entry.name or "")
        if n ~= "" then
            vocab.conditions[n] = {
                indefiniteDuration = entry:try_get("indefiniteDuration", false),
            }
            -- Add each whitespace-separated word of the condition name
            -- to the search tokens (most are single-word, but defensive).
            for word in n:gmatch("[a-z]+") do
                addToken(word, "condition")
            end
        end
    end

    -- 3. Riders: importer-pattern friendly labels. Multi-word entries
    --    are kept whole for prefix display, plus each constituent word
    --    enters the search pool.
    local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName) or {}
    for _,entry in unhidden_pairs(ridersTable) do
        local label = entry:try_get("powerTableText", "")
        local n = string.lower(label)
        if n ~= "" then
            vocab.riderNames[n] = true
            for word in n:gmatch("[a-z]+") do
                addToken(word, "rider")
            end
        end
    end

    -- 4. Built-in mechanical keywords: walk g_rulePatterns and lift
    --    literal alphabetic words out of each pattern. Catches things
    --    like push/pull/slide/teleport/shift/jump/swap that aren't in
    --    any data table.
    for _,entry in ipairs(g_rulePatterns) do
        local patterns = entry.pattern
        if type(patterns) == "string" then
            ExtractDiagnosticWordsFromPattern(patterns, vocab.keywords)
        elseif type(patterns) == "table" then
            for _,p in ipairs(patterns) do
                ExtractDiagnosticWordsFromPattern(p, vocab.keywords)
            end
        end
    end
    for word in pairs(vocab.keywords) do
        addToken(word, "keyword")
    end

    -- 5. Importer-curated mechanical vocabulary. Lifted from every
    --    active importerPowerTableEffects pattern. These are the
    --    custom words the importer recognises (illuminated,
    --    shapechanged, stamina, surge, ...) plus generic connective
    --    glue (target, save, ends). Added to searchTokens so they
    --    populate knownWordsLookup (Kind 1 won't try to near-miss
    --    them), but FindNearMiss filters out non-curated kinds at
    --    suggestion time so these tokens are never returned as
    --    suggestions - too noisy. See vocab.ongoingEffects below
    --    for the curated counterpart pulled from a real data table.
    local rulesTable = dmhub.GetTable("importerPowerTableEffects") or {}
    for _,entry in unhidden_pairs(rulesTable) do
        local importMatch = entry:try_get("importMatch", nil)
        if type(importMatch) == "string" and importMatch ~= "" then
            ExtractDiagnosticWordsFromPattern(string.lower(importMatch), vocab.importerKeywords)
        end
    end
    for word in pairs(vocab.importerKeywords) do
        addToken(word, "importerKeyword")
    end

    -- 6. Ongoing effects: single-word names from the
    --    characterOngoingEffects table - illuminated, shapechanged,
    --    burning, foesense, rage, hidden, etc. Multi-word names
    --    (e.g. "Burning Ash Target") are skipped because they're
    --    encounter-specific instances rather than reusable
    --    mechanical vocabulary. This bucket is the durable
    --    high-confidence near-miss target for custom mechanics:
    --    typing "illumnated" suggests "illuminated" because the
    --    name exists as a data record, not because it appears in
    --    an importer regex.
    vocab.ongoingEffects = {}
    local ongoingTable = dmhub.GetTable("characterOngoingEffects") or {}
    for _, entry in unhidden_pairs(ongoingTable) do
        local name = entry:try_get("name", "")
        if type(name) == "string" and name ~= "" then
            local lowered = string.lower(name)
            if lowered:match("^[a-z]+$") then
                vocab.ongoingEffects[lowered] = true
                addToken(lowered, "ongoingEffect")
            end
        end
    end

    return vocab
end

local function BuildDiagnosticCompendiumKeywords()
    -- Compendium suppression was scoped out during Chunk 5 testing.
    -- The original spec intended to silence Kind 4 on tails that
    -- mention importer-curated mechanic words ("illuminated",
    -- "shapechanged", ...), but in practice every variant of the
    -- importer-pattern subtraction or frequency filter let generic
    -- English glue ("until", "ally", "within") into the set,
    -- silencing legitimate Kind 4 chips. Bronze+ status gating
    -- already wholesale-suppresses Kind 4, and Unimplemented authors
    -- want max feedback, so the suppression set has been emptied.
    -- The cache key and callers stay in place so the spec section
    -- can be revisited later without code churn.
    return {}
end

--- Returns the cached diagnostic vocabulary. Rebuilds on first
--- call after refreshTables.
--- @return table
function ActivatedAbilityDrawSteelCommandBehavior.GetDiagnosticVocab()
    if g_diagnosticVocabCache == nil then
        g_diagnosticVocabCache = BuildDiagnosticVocab()
    end
    return g_diagnosticVocabCache
end

--- Returns the cached compendium-pattern keyword suppression set.
--- Tokens in this set are treated as authored prose and silence the
--- Unknown-segment diagnostic for the segment they appear in.
--- @return table<string, boolean>
function ActivatedAbilityDrawSteelCommandBehavior.GetCompendiumDiagnosticKeywords()
    if g_diagnosticCompendiumKeywordCache == nil then
        g_diagnosticCompendiumKeywordCache = BuildDiagnosticCompendiumKeywords()
    end
    return g_diagnosticCompendiumKeywordCache
end

dmhub.RegisterEventHandler("refreshTables", function(keys)
    if mod.unloaded then return end
    g_diagnosticVocabCache = nil
    g_diagnosticCompendiumKeywordCache = nil
end)

----------------------------------------------------------------
-- Diagnostician: parsed-segment walker + DiagnoseTierText engine
----------------------------------------------------------------
-- WalkParsedSegments re-runs the same parser flow as ValidateRule
-- but yields each successfully-matched segment alongside the final
-- unparsed tail. DiagnoseTierText consumes that output and produces
-- structured findings (one per actionable issue) for the chip
-- strip UI to format. No string assembly happens here - chip copy
-- lives with the UI - so this layer stays a pure data transform.

-- Damerau-Levenshtein (Optimal String Alignment variant) with early
-- abort when the running minimum exceeds maxDist. Standard
-- Levenshtein treats adjacent-letter transpositions as TWO edits,
-- which under-fires on common typing typos like "fier" -> "fire"
-- (a single transposition of "ie" -> "ie") because their distance
-- is 2 and the threshold for short vocab words (< 6 chars) is 1.
-- The OSA variant counts a transposition as one edit, so "fier"
-- correctly near-misses "fire" at distance 1. Three rows tracked
-- (prev2, prev, curr) so the transposition step can look back one
-- extra row. Same O(m*n) time, O(min(m,n)) space. Returns maxDist+1
-- on early bail.
local function LevenshteinDistance(a, b, maxDist)
    if a == b then return 0 end
    local la, lb = #a, #b
    if math.abs(la - lb) > maxDist then return maxDist + 1 end
    local prev2 = {}
    local prev, curr = {}, {}
    for j = 0, lb do prev[j] = j end
    local prevA = ""
    for i = 1, la do
        curr[0] = i
        local rowMin = curr[0]
        local ai = a:sub(i, i)
        local prevB = ""
        for j = 1, lb do
            local bj = b:sub(j, j)
            local cost = ai == bj and 0 or 1
            local v = prev[j] + 1
            local v2 = curr[j-1] + 1
            if v2 < v then v = v2 end
            local v3 = prev[j-1] + cost
            if v3 < v then v = v3 end
            if i > 1 and j > 1 and ai == prevB and prevA == bj then
                local vt = prev2[j-2] + 1
                if vt < v then v = vt end
            end
            curr[j] = v
            if v < rowMin then rowMin = v end
            prevB = bj
        end
        if rowMin > maxDist then return maxDist + 1 end
        -- Rotate rows: prev2 <- prev, prev <- curr, curr <- prev2 (reuse).
        local tmp = prev2
        prev2 = prev
        prev = curr
        curr = tmp
        prevA = ai
    end
    return prev[lb]
end

-- Find the closest vocab token to `word` within Levenshtein 1, or
-- Levenshtein 2 when the vocab word is >= 6 chars (the spec rule
-- from the project doc). Optionally filter by kind to scope the
-- search - e.g. Kind 3 only wants damage-type suggestions.
-- High-confidence vocab kinds that FindNearMiss is allowed to
-- suggest. Limiting suggestions to these kinds eliminates a large
-- class of false positives where a generic word in the
-- pattern-extracted "keyword"/"importerKeyword" buckets (e.g.
-- "cant", "another", "choose", "net", "end") was offered as a
-- correction for a common English word in author prose. These four
-- kinds are all derived from curated data tables - damage types,
-- conditions, condition riders, single-word ongoing-effect names -
-- so they don't drift as new content lands. New importer patterns
-- can add words that authors should know about, but those words
-- typically have a corresponding ongoing-effect record we'll pick
-- up anyway.
local g_diagnosticHighConfidenceKinds = {
    damageType = true,
    condition = true,
    rider = true,
    ongoingEffect = true,
}

-- Returns {word, kind, distance} or nil.
--
-- Threshold is Damerau-Levenshtein distance 1 across the board.
-- The earlier "distance 2 allowed for vocab words >= 6 chars" rule
-- caught the spec-cited "fier" -> "fire" case but also produced
-- cross-word false positives at distance 2 (charges -> charmed,
-- whose -> choose, other -> another) where the input is a real
-- English word that happens to be 2 edits from a curated mechanic.
-- The Damerau variant counts adjacent transpositions as a single
-- edit, so "fier" -> "fire" stays detected (it's a transposition).
-- Genuine distance-2 typos (two unrelated edits in one word) are
-- rare enough that the false-positive reduction is worth the loss.
local function FindNearMiss(word, kindFilter)
    if word == nil or #word < 3 then return nil end
    local vocab = ActivatedAbilityDrawSteelCommandBehavior.GetDiagnosticVocab()
    local tokens = vocab.searchTokens
    if tokens == nil then return nil end

    local best = nil
    local bestDist = 2
    for _,entry in ipairs(tokens) do
        if g_diagnosticHighConfidenceKinds[entry.kind]
                and (kindFilter == nil or entry.kind == kindFilter) then
            local d = LevenshteinDistance(word, entry.word, 1)
            if d == 1 and d < bestDist then
                bestDist = d
                best = entry
            end
        end
    end

    if best == nil then return nil end
    return {word = best.word, kind = best.kind, distance = bestDist}
end

-- Tokenise a segment into lowercase alphabetic word runs (>= 3
-- chars). Used to scan the unparsed tail for near-miss matches and
-- to drive the compendium suppression check.
local function TokeniseSegment(segment)
    -- Stopword filter applied here as well as during vocab build:
    -- without it, words that are in g_diagnosticStopwords (like
    -- "and", "all", "not", number words) still get tokenised and
    -- hit FindNearMiss, producing false-positive Kind 1 chips
    -- ("and -> end", "all -> ally", "five -> fire") on legitimate
    -- prose.
    local words = {}
    if type(segment) ~= "string" then return words end
    for word in string.lower(segment):gmatch("[a-z]+") do
        if #word >= 3 and not g_diagnosticStopwords[word] then
            words[#words+1] = word
        end
    end
    return words
end

-- Does the segment carry a duration suffix? Matches (save ends),
-- (EoT), (EoE) and their lowercase forms, with or without
-- surrounding whitespace. Mirrors the duration tokens recognised
-- by g_rulePatterns at lines 543, 651, 1271 etc.
local function SegmentHasDurationSuffix(segment)
    if type(segment) ~= "string" then return false end
    local lowered = string.lower(segment)
    if lowered:find("%(%s*save%s+ends%s*%)") then return true end
    if lowered:find("%(%s*eot%s*%)") then return true end
    if lowered:find("%(%s*eoe%s*%)") then return true end
    return false
end

--- Walk the parsed structure of `rule` the same way ValidateRule
--- does. Returns a list of segment records:
---   {kind = "gate" | "importer" | "builtin" | "unparsed",
---    text = string,           -- the matched (or unparsed) text
---    match = nil | table,     -- regex match groups when matched
---    entry = nil | table,     -- the g_rulePatterns/importer entry
---    pattern = nil | string}  -- which alternative pattern hit
-- Strip characteristic-bonus shorthand (e.g. "3 + M damage" or
-- "3 + M or A damage") down to just the base number, mirroring
-- runtime NormalizeDamageRuleTextForCreature but with no caster.
-- The runtime substitutes the actual attribute value before pattern
-- matching, which means the damage regex sees a clean number. The
-- diagnostician walks patterns without a caster context, so we have
-- to perform the same erasure here - otherwise Pattern A captures
-- the bonus letter ("m"/"a"/"r"/"i"/"p") as if it were a damage
-- type, producing a spurious Kind 3 "Damage type m isn't recognized"
-- chip on every characteristic-bonus tier.
local function NormalizeRuleForDiagnostic(rule)
    -- Multi-attribute form: "N + M or A" / "N + M, A or I"
    local matchCharBonus = regex.MatchGroups(rule,
        "^(?<prefix>.*?)(?<number>[0-9]+)\\s*\\+\\s*(?<attr>[MARIPmarip, ]+,? or [MARIPmarip]+)(\\s*(?<suffix>.*)|(?<suffix>[;,].*))?$")
    if matchCharBonus == nil then
        -- Single-attribute form: "N + M"
        matchCharBonus = regex.MatchGroups(rule,
            "^(?<prefix>.*?)(?<number>[0-9]+)\\s*\\+\\s*(?<attr>[MARIPmarip](?![A-Za-z]))(\\s*(?<suffix>.*)|(?<suffix>[;,].*))?$")
    end
    if matchCharBonus ~= nil then
        return matchCharBonus.prefix .. matchCharBonus.number .. " " .. (matchCharBonus.suffix or "")
    end
    return rule
end

-- The "#" sigil in tier text is the author's opt-out-of-parsing
-- marker. DisplayRuleTextForCreature renders everything from " #"
-- (or a leading "#") with an invisible alpha tag at runtime, so the
-- substantive parser never sees that tail - it's typically prose
-- the author is automating via behaviours (InflictCondition, aura
-- effects, custom behaviour). The diagnostician has to honour the
-- same rule or it generates spurious chips on every # block (e.g.
-- "slowed needs a duration" when the author is applying slowed via
-- an aura, not via the rule text).
--
-- We truncate AT the "#" (not before its preceding space) so the
-- gate prefix's required trailing space stays intact - otherwise
-- "p < average, #prose" would strip to "p < average," and the gate
-- regex (which demands "?, " or "? " trailing) would fail.
local function StripHashStopMarker(rule)
    local hashIdx = string.find(rule, "#", 1, true)
    if hashIdx == nil then return rule end
    if hashIdx == 1 then return "" end
    return string.sub(rule, 1, hashIdx - 1)
end

--- @param rule string
--- @return table
function ActivatedAbilityDrawSteelCommandBehavior.WalkParsedSegments(rule)
    local segments = {}
    if type(rule) ~= "string" or rule == "" then return segments end
    rule = string.lower(rule)
    rule = NormalizeRuleForDiagnostic(rule)
    rule = StripHashStopMarker(rule)

    -- Pull the potency gate off the front exactly the way
    -- ValidateRule does - the diagnostician treats it as already-
    -- understood structure, not a candidate for chips.
    local gateMatch = regex.MatchGroups(rule, "^(?<head>.*?)(?<gate>(<color=[^>]+>)?(<uppercase>)?[marip](</uppercase>)? ?< ?\\[?(-?[0-9]+|weak|average|strong)\\]?(</color>)?,? )(?<tail>[^;]*)(?<rest>;.*)?$")
    if gateMatch ~= nil then
        segments[#segments+1] = {kind = "gate", text = gateMatch.gate, match = gateMatch}
        rule = gateMatch.head .. gateMatch.tail .. (gateMatch.rest or "")
    end

    local guard = 64
    while rule ~= "" and guard > 0 do
        guard = guard - 1
        local advanced = false

        -- 1. Importer table (highest priority, longest match wins).
        local bestMatchInfo = nil
        local bestPatternEntry = nil
        local rulesTable = dmhub.GetTable("importerPowerTableEffects") or {}
        for _,patternEntry in unhidden_pairs(rulesTable) do
            local abilityMatch, matchInfo = patternEntry:MatchMCDMEffect(nil, "Ability", rule)
            if abilityMatch ~= nil then
                if matchInfo == nil then
                    -- Full-match (no captures) - treat as the whole rule.
                    bestMatchInfo = {all = rule}
                    bestPatternEntry = patternEntry
                    break
                end
                if bestMatchInfo == nil or (matchInfo.all and #matchInfo.all > #(bestMatchInfo.all or "")) then
                    bestMatchInfo = matchInfo
                    bestPatternEntry = patternEntry
                end
            end
        end

        if bestMatchInfo ~= nil and bestMatchInfo.all ~= nil then
            segments[#segments+1] = {
                kind = "importer",
                text = bestMatchInfo.all,
                match = bestMatchInfo,
                entry = bestPatternEntry,
            }
            rule = string.sub(rule, #bestMatchInfo.all + 1)
            local sep = regex.MatchGroups(rule, "^ *[;,] *(?<body>.+)$")
            if sep ~= nil then rule = sep.body end
            advanced = true
        end

        if not advanced then
            -- 2. Built-in g_rulePatterns.
            for _,entry in ipairs(g_rulePatterns) do
                local patterns = entry.pattern
                if type(patterns) == "string" then patterns = {patterns} end
                for _,p in ipairs(patterns) do
                    local match = regex.MatchGroups(rule, p)
                    if match ~= nil and (entry.validate == nil or entry.validate(entry, match)) then
                        segments[#segments+1] = {
                            kind = "builtin",
                            text = match.all,
                            match = match,
                            entry = entry,
                            pattern = p,
                        }
                        rule = string.sub(rule, #(match.all or rule) + 1)
                        local sepMatch = regex.MatchGroups(rule, "^( *, *| *and *| *then *| *; *)")
                        if sepMatch == nil then
                            sepMatch = regex.MatchGroups(rule, "^ ")
                        end
                        if sepMatch ~= nil then
                            rule = string.sub(rule, #sepMatch.all + 1)
                        end
                        advanced = true
                        break
                    end
                end
                if advanced then break end
            end
        end

        if not advanced then
            -- Nothing recognised the head of the remaining rule.
            -- Capture the rest as the unparsed tail and stop.
            if string.find(rule, "%S") then
                segments[#segments+1] = {kind = "unparsed", text = rule}
            end
            break
        end
    end

    return segments
end

-- Inspect a parsed `builtin` damage segment for an unknown damage
-- type. Returns a finding or nil. When a near-miss exists the
-- finding combines Kind 3 with Kind 1; otherwise it's bare Kind 3.
local function DiagnoseDamageSegment(segment, vocab)
    if segment.match == nil then return nil end
    local damageType = segment.match.type
    if damageType == nil or damageType == "" then return nil end
    damageType = string.lower(damageType)
    if vocab.damageTypes[damageType] then return nil end

    local nearMiss = FindNearMiss(damageType, "damageType")
    return {
        kind = "damageType_unknown",
        severity = "warning",
        token = damageType,
        suggestion = nearMiss and nearMiss.word or nil,
        segment = segment.text,
        -- Build the suggested-rewrite preview by swapping in the
        -- suggested damage type; the UI uses this for the tooltip.
        tooltipPreview = nearMiss and (segment.text:gsub(damageType, nearMiss.word, 1)) or nil,
    }
end

-- Inspect the unparsed tail for Kinds 1/2/4. Diagnostic order:
--   1. Kind 2 (missing duration)  - high-confidence
--   2. Kind 1 (did-you-mean)      - high-confidence
--   3. Kind 4 (unknown segment)   - catch-all, subject to compendium suppression
-- Kinds 1/2 always fire when their conditions are met, even if the
-- segment also contains importer-curated tokens, because a clear
-- typo or missing duration is a real issue regardless of surrounding
-- glue. Compendium suppression applies ONLY to Kind 4: if any token
-- in the segment is in the importer-curated vocabulary, we trust
-- the importer's pattern set and stay silent on the catch-all.
local function DiagnoseUnparsedSegment(segment, vocab, compendiumKeywords, knownWordsLookup)
    local findings = {}
    local text = segment.text
    if type(text) ~= "string" or string.find(text, "%S") == nil then
        return findings
    end

    local words = TokeniseSegment(text)
    if #words == 0 then
        return findings
    end

    -- Kind 2: Missing duration. Fires if any tokenised word is a
    -- known condition that does NOT carry the indefiniteDuration
    -- flag, and no duration suffix follows.
    local hasDuration = SegmentHasDurationSuffix(text)
    if not hasDuration then
        for _,w in ipairs(words) do
            local condInfo = vocab.conditions[w]
            if condInfo and not condInfo.indefiniteDuration then
                findings[#findings+1] = {
                    kind = "duration_missing",
                    severity = "warning",
                    condition = w,
                    segment = text,
                }
                break -- one duration chip per segment is enough
            end
        end
    end

    -- Kind 1: Did-you-mean. Walk tokens; first near-miss wins.
    -- Skip tokens that are already in the vocab (known words) or
    -- already covered by a duration finding (same word). The
    -- knownWordsLookup is the union of every vocab bucket so we
    -- don't suggest typo corrections for words that legitimately
    -- live in vocab (e.g. rider-name components like "tail").
    local kind1Word = nil
    local kind1Suggestion = nil
    local conditionAlreadyFlagged = nil
    if #findings > 0 and findings[1].kind == "duration_missing" then
        conditionAlreadyFlagged = findings[1].condition
    end
    for _,w in ipairs(words) do
        if w ~= conditionAlreadyFlagged and not knownWordsLookup[w] then
            local nm = FindNearMiss(w, nil)
            if nm ~= nil then
                kind1Word = w
                kind1Suggestion = nm.word
                break
            end
        end
    end

    if kind1Word ~= nil then
        findings[#findings+1] = {
            kind = "near_miss",
            severity = "warning",
            token = kind1Word,
            suggestion = kind1Suggestion,
            segment = text,
            -- Tooltip preview swaps the typo for its suggestion
            -- in the original segment so the author sees the
            -- corrected form.
            tooltipPreview = text:gsub(kind1Word, kind1Suggestion, 1),
        }
        return findings
    end

    -- Kind 4: Unknown segment. Catch-all when Kinds 1/2 didn't
    -- fire. Compendium suppression applies here only: if the tail
    -- contains an importer-curated token (the post-subtraction set
    -- built in BuildDiagnosticCompendiumKeywords - excludes generic
    -- glue like "target"/"save"/"ends") we treat it as known prose
    -- and stay silent. Bronze+ will also suppress Kind 4 via the
    -- status gating layer.
    if #findings == 0 then
        for _,w in ipairs(words) do
            if compendiumKeywords[w] then
                return findings
            end
        end
        findings[#findings+1] = {
            kind = "unknown_segment",
            severity = "neutral",
            segment = text,
        }
    end

    return findings
end

--- Run the diagnostician over a single tier rule string. Returns
--- a list of finding records the chip-strip UI can render. The
--- engine doesn't filter by implementation status - status gating
--- (Bronze+ collapse + Kind 4 suppression) is the caller's job.
---
--- Finding shape:
---   {
---     kind = "damageType_unknown" | "duration_missing"
---          | "near_miss"          | "unknown_segment",
---     severity = "warning" | "neutral",
---     -- one or more of these slots filled depending on kind:
---     token = string,           -- offending word (1, 3)
---     suggestion = string,      -- near-miss target (1, optionally 3)
---     condition = string,       -- condition word (2)
---     segment = string,         -- the segment text the chip refers to
---     tooltipPreview = string,  -- rewritten clause for tooltip (1, 3+1)
---   }
--- @param rule string
--- @return table[]
function ActivatedAbilityDrawSteelCommandBehavior.DiagnoseTierText(rule)
    local findings = {}
    if type(rule) ~= "string" or rule == "" then return findings end

    local vocab = ActivatedAbilityDrawSteelCommandBehavior.GetDiagnosticVocab()
    local compendiumKeywords = ActivatedAbilityDrawSteelCommandBehavior.GetCompendiumDiagnosticKeywords()

    -- Flat membership set: word -> true for every searchToken in
    -- the vocab, PLUS common English plural variants of each. Used
    -- by the unparsed-segment diagnosis to skip known words before
    -- running expensive near-miss lookup. The plural-variant pass
    -- prevents Kind 1 false-positives on singular/plural pairs
    -- where only one form is in vocab (e.g. "roll" in vocab but
    -- "rolls" not - the author's "ability rolls" would otherwise
    -- near-miss to "roll"). Heuristic plural forms covered:
    --   add "s"                  : roll -> rolls
    --   strip "y", add "ies"     : ally -> allies
    --   add "es" after sibilant  : bonus -> bonuses, witch -> witches
    -- Reverse direction also covered: if the plural is in vocab,
    -- accept the singular too.
    local knownWordsLookup = {}
    local function markKnown(w)
        if w == nil or w == "" then return end
        knownWordsLookup[w] = true
    end
    for _,t in ipairs(vocab.searchTokens) do
        local w = t.word
        markKnown(w)
        -- Forward plurals (vocab has singular; accept plural input)
        markKnown(w .. "s")
        if w:sub(-1) == "y" then
            markKnown(w:sub(1, -2) .. "ies")
        end
        local tail2 = w:sub(-2)
        if tail2 == "ch" or tail2 == "sh" or w:sub(-1) == "s" or w:sub(-1) == "x" or w:sub(-1) == "z" then
            markKnown(w .. "es")
        end
        -- Reverse direction (vocab has plural; accept singular input)
        if w:sub(-1) == "s" and #w > 3 then
            markKnown(w:sub(1, -2))
        end
        if w:sub(-3) == "ies" and #w > 4 then
            markKnown(w:sub(1, -4) .. "y")
        end
        if w:sub(-2) == "es" and #w > 4 then
            markKnown(w:sub(1, -3))
        end
    end

    local segments = ActivatedAbilityDrawSteelCommandBehavior.WalkParsedSegments(rule)
    for _,segment in ipairs(segments) do
        if segment.kind == "builtin" and segment.entry and segment.entry.isdamage then
            local f = DiagnoseDamageSegment(segment, vocab)
            if f ~= nil then findings[#findings+1] = f end
        elseif segment.kind == "unparsed" then
            local segFindings = DiagnoseUnparsedSegment(segment, vocab, compendiumKeywords, knownWordsLookup)
            for _,f in ipairs(segFindings) do
                findings[#findings+1] = f
            end
        end
    end

    return findings
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

Commands.RegisterMacro{
    name = "download",
    summary = "debug export class",
    doc = "Usage: /download\nExports the Fury class to a debug JSON file.",
    command = function()
        local classes = dmhub.GetTable("classes")
        for k,v in pairs(classes) do
            if v.name == "Fury" then
                dmhub.DebugFileWriteObject("d:/dev/debug/class.json", v)
            end
        end
    end,
}

Commands.RegisterMacro{
    name = "upload",
    summary = "debug import class",
    doc = "Usage: /upload\nImports the Fury class from a debug JSON file.",
    command = function()
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
    end,
}
--Per-encounter hero stats: forced movement distance. Every forced-movement flow
--(tier-text push/pull/slide commands above, ActivatedAbilityForcedMovementBehavior,
--and direct/remote invokes of the standard "Forced Movement: X" abilities) funnels
--into a relocate_creature cast of a clone whose range has already been adjusted
--for stability, Big Versus Little, Forced Movement Increase, and caster bonuses --
--and whose "forcedMovement" field carries the movement type. So we wrap the
--relocate Cast here, in the Draw Steel layer, and record the clone's range as the
--distance: that is the entitlement the rules granted, which the user-facing stat
--should count even when a wall or creature stops the actual path short (a push 5
--into a wall after 2 squares still counts as 5). Mirrors the abilityDist
--computation inside the base Cast (range / unitsPerSquare).
--
--forcedMovementTaken: credited to the moved creature (the clone's caster).
--forcedMovementDealt: credited to the pusher (the clone's invoker), only when the
--moved creature is an enemy -- repositioning allies is not "moving your enemies".
--TrackHeroStats self-guards to heroes in the live encounter, so monster pushers
--and monster victims are dropped, and a hero's summon credits the hero.
local g_baseRelocateCreatureCast = ActivatedAbilityRelocateCreatureBehavior.Cast
function ActivatedAbilityRelocateCreatureBehavior:Cast(ability, casterToken, targets, options)
    g_baseRelocateCreatureCast(self, ability, casterToken, targets, options)

    local forcedMovementType = ability:try_get("forcedMovement")
    if forcedMovementType == nil or forcedMovementType == "" then
        return
    end

    --Forced movement clones use movementType "move"; teleports and jumps are not
    --forced movement and never count.
    local movementType = self.movementType
    if options.symbols ~= nil and options.symbols.shiftingOverride == false then
        movementType = "move"
    end
    if movementType ~= "move" then
        return
    end

    local spaces = round(ability:GetRange(casterToken.properties) / dmhub.unitsPerSquare)
    if spaces <= 0 then
        return
    end

    LiveEncounter.TrackHeroStats(casterToken.charid, "forcedMovementTaken", spaces)

    local invoker = ability:try_get("invoker")
    if invoker == nil and options.symbols ~= nil and options.symbols.invoker ~= nil then
        invoker = options.symbols.invoker
        if type(invoker) == "function" then
            invoker = invoker("self")
        end
    end

    if invoker ~= nil then
        local pusherToken = dmhub.LookupToken(invoker)
        if pusherToken ~= nil and pusherToken.charid ~= casterToken.charid and (not pusherToken:IsFriend(casterToken)) then
            LiveEncounter.TrackHeroStats(pusherToken.charid, "forcedMovementDealt", spaces)
        end
    end
end
