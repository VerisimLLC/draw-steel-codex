local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityInvokeAbilityBehavior
ActivatedAbilityInvokeAbilityBehavior = RegisterGameType("ActivatedAbilityInvokeAbilityBehavior", "ActivatedAbilityBehavior")

--- @class AbilityInvocation
AbilityInvocation = RegisterGameType("AbilityInvocation")

AbilityUtils = {
	--utility to scan an ability for e.g. <<range>> and extract all parameters.
	ExtractAbilityParameters = function(node, output)
		if type(node) ~= "table" then
			return
		end

		for k,v in pairs(node) do
			if type(v) == "string" and k ~= "importMatch" then
				local s = v

				for count=1,8 do
					local match = regex.MatchGroups(s, "^.*?<<(?<name>[a-zA-Z_]+)(?<defaultValue>=[0-9 a-zA-Z]*)?>>(?<tail>.*)$")
					if match == nil then
						break
					end

                    print("EXTRACT:: MATCH", match.name, match.defaultValue or "no default", "FROM", s, "KEY =", k)

                    local defaultValue = ""

                    if match.defaultValue then
                        defaultValue = string.sub(match.defaultValue, 2) --remove the = from the default value.
                    end

					output[match.name] = {defaultValue = defaultValue}
					s = match.tail
				end

			elseif type(v) == "table" then
				AbilityUtils.ExtractAbilityParameters(v, output)
			end
		end
	end,

	DeepReplaceAbility = function(node, from, to)
		if type(node) ~= "table" then
			return
		end

        if string.starts_with(from, "<<") and string.ends_with(from, ">>") then
            --add in a regex match for the default value, =.* as an optional part of the parameter name, before the >>.
            from = string.sub(from, 1, -3) .."(=[0-9 a-zA-Z]*)?"..string.sub(from, -2)
        end

		for k,v in pairs(node) do
			if v == from then
				node[k] = to
			elseif type(v) == "string" then
				node[k] = regex.ReplaceAll(v, from, to)
			else
				AbilityUtils.DeepReplaceAbility(v, from, to)
			end
		end
	end,

    SetDefaultParameters = function(node, from)
		if type(node) ~= "table" then
			return
		end
		for k,v in pairs(node) do
            if type(v) == "string" then
                local s = v
                local match = regex.MatchGroups(s, "^.*?<<" .. from .. "(?<defaultValue>=[0-9 a-zA-Z]*)?>>(?<tail>.*)$")

                if match ~= nil then
                    local defaultValue = match.defaultValue or ""
                    if string.starts_with(defaultValue, "=") then
                        defaultValue = string.sub(defaultValue, 2) --remove the = from the default value.
                    end

                    if defaultValue == "" then
                        node[k] = regex.ReplaceAll(s, "<<" .. from .. ">>", "")
                    else
                        node[k] = regex.ReplaceAll(s, "<<" .. from .. "=[0-9 a-zA-Z]*>>", defaultValue)
                    end
                end
            else
                AbilityUtils.SetDefaultParameters(v, from)
            end
        end
    end,

	--utility to scan for an <<expression>> in a string and evaluate it as goblin script.
	--Useful to evaluate in the context of the caster.
	SubstituteAbilityParameters = function(str, symbols)
        str = StringInterpolateGoblinScript(str, symbols)
		local result = ""
		for i=1,8 do
			local match = regex.MatchGroups(str, "^(?<head>.*)?<<(?<expression>.*?)>>(?<tail>.*)$")
			if match == nil then
				result = result .. str
				break
			end

			result = result .. match.head

            local val = dmhub.EvalGoblinScript(match.expression, symbols, "Substitute parameter in invocation") 
			result = result .. val

			str = match.tail
		end

		return result
	end,
}



ActivatedAbility.RegisterType
{
	id = 'invoke_ability',
	text = 'Invoke Ability',
	createBehavior = function()
		local customAbility = ActivatedAbility.Create()
		customAbility.name = "Invoked Ability"
		return ActivatedAbilityInvokeAbilityBehavior.new{
			customAbility = customAbility,
		}
	end,
}

ActivatedAbilityInvokeAbilityBehavior.summary = 'Invoke Ability'
ActivatedAbilityInvokeAbilityBehavior.promptText = ''

--if true we will invoke on the caster token.
ActivatedAbilityInvokeAbilityBehavior.invokeOnCaster = false
ActivatedAbilityInvokeAbilityBehavior.runOnController = false
ActivatedAbilityInvokeAbilityBehavior.rangeOrigin = ""

--If false (the default), the invoked ability will not use squad coordination even if
--it would normally (signature abilities, free strikes, other Strike-keyworded
--abilities, and squad maneuvers). Set true to opt in.
ActivatedAbilityInvokeAbilityBehavior.useSquadCoordination = false

local function GetParentPrimaryTargetTokenId(options)
    local cast = options ~= nil and options.symbols ~= nil and options.symbols.cast or nil
    for _,target in ipairs(cast ~= nil and cast.targets or {}) do
        local targetToken = target.token
        if targetToken ~= nil and targetToken.valid and targetToken.id ~= nil then
            return targetToken.id
        end
    end

    return nil
end

--Squad caster-side invokes receive the main attacker as their current target.
--Reverse its targetPairs entry to recover the parent target that attacker chose.
local function GetParentCurrentTargetTokenId(options, currentToken)
    local symbols = options ~= nil and options.symbols or nil
    if symbols ~= nil and currentToken ~= nil then
        for _,pair in ipairs(symbols.targetPairs or {}) do
            if pair.a == currentToken.charid or pair.a == currentToken.id then
                local targetToken = dmhub.GetTokenById(pair.b)
                if targetToken ~= nil and targetToken.valid and targetToken.id ~= nil then
                    return targetToken.id
                end
            end
        end
    end

    return GetParentPrimaryTargetTokenId(options)
end

--Pulls every ActivatedAbility granted by a feature's "activated" modifiers into result,
--stamping each clone with the class metadata that the chooseClassAbility filter reads.
--- @param feature CharacterFeature
--- @param info {classLevel: number, levelsAbove: number, className: string, prerequisitesMet: boolean, known: table<string,boolean>}
--- @param result ActivatedAbility[]
local function CollectFeatureAbilities(feature, info, result)
    for _,modifier in ipairs(feature:try_get("modifiers", {})) do
        if modifier:try_get("behavior") == "activated" then
            local grantedAbility = modifier:try_get("activatedAbility")
            if grantedAbility ~= nil then
                local candidate = grantedAbility:MakeTemporaryClone()

                --_tmp_ fields are skipped by the serializer, so this metadata never
                --reaches the database even though the clone gets cast for real.
                candidate._tmp_classLevel = info.classLevel
                candidate._tmp_levelsAbove = info.levelsAbove
                candidate._tmp_className = info.className
                candidate._tmp_prerequisitesMet = info.prerequisitesMet
                candidate._tmp_abilityKnown = info.known[string.lower(candidate.name)] == true

                result[#result+1] = candidate
            end
        end
    end
end

--Harvests every activated ability offered by the level lists of the caster's classes,
--subclasses and domains. Nothing is filtered here beyond structure -- the GoblinScript
--abilityFilter decides what the player actually sees, reading the stamped metadata via
--Ability.Class Level / Levels Above / Class / Known / Prerequisites Met.
--- @param casterToken nil|CharacterToken
--- @return ActivatedAbility[]
local function GatherClassAbilities(casterToken)
    local result = {}

    local creature = casterToken ~= nil and casterToken.properties or nil
    if creature == nil then
        return result
    end

    --Monsters and other non-character creatures have no class list -- the base
    --creature implementation returns an empty table, so this is safe to call.
    local classEntries = creature:GetClassesAndSubClasses()
    if classEntries == nil or #classEntries == 0 then
        return result
    end

    --Abilities the character already has, keyed by lowercased name. Matching by name
    --rather than guid because a class option and the character's granted copy of it
    --are distinct objects with distinct guids.
    local known = {}
    for _,a in ipairs(creature:GetActivatedAbilities{ characterSheet = true }) do
        if a.name ~= nil then
            known[string.lower(a.name)] = true
        end
    end

    local levelChoices = creature:GetLevelChoices() or {}

    for _,entry in ipairs(classEntries) do
        local classInfo = entry.class
        local currentLevel = entry.level or 0

        --Read the levels table directly rather than via Class:GetLevel, which creates
        --a fresh ClassLevel for any key it doesn't find -- we must not mutate the
        --shared, cached class objects just to look at them.
        for key,levelEntry in pairs(classInfo:try_get("levels", {})) do
            --Level-1 content is NOT under "level-1" -- per Class:FillLevelsUpTo, a
            --character's progression is "primary", then "tutoriallevel-1".."tutoriallevel-4",
            --then "level-1".."level-N". The tutoriallevel-* entries are always included
            --regardless of level; they are how level 1 is split into builder stages, and
            --for most classes they hold ALL the level-1 features (including the 3- and
            --5-cost heroic ability choices, while "level-1" itself is empty). Treat them
            --as level 1. "multiclass" is the secondary-class variant of "primary" and is
            --deliberately skipped.
            local levelNum = tonumber(string.match(key, "^level%-(%d+)$"))
            if levelNum == nil and (key == "primary" or string.match(key, "^tutoriallevel%-%d+$") ~= nil) then
                levelNum = 1
            end

            if levelNum ~= nil and levelEntry ~= nil then
                local info = {
                    classLevel = levelNum,
                    levelsAbove = levelNum - currentLevel,
                    className = classInfo.name or "",
                    prerequisitesMet = true,
                    known = known,
                }

                for _,feature in ipairs(levelEntry:try_get("features", {})) do
                    if feature.typeName == "CharacterFeatureChoice" then
                        for _,option in ipairs(feature:GetOptions(levelChoices)) do
                            --A feature is only offered if every prerequisite on it is
                            --met. Exposed as a symbol rather than filtered out here so
                            --content can choose to ignore it.
                            local prerequisitesMet = true
                            for _,prerequisite in ipairs(rawget(option, "prerequisites") or {}) do
                                if not prerequisite:Met(creature) then
                                    prerequisitesMet = false
                                end
                            end

                            info.prerequisitesMet = prerequisitesMet
                            CollectFeatureAbilities(option, info, result)
                        end
                    else
                        info.prerequisitesMet = true
                        CollectFeatureAbilities(feature, info, result)
                    end
                end
            end
        end
    end

    return result
end

--Runs the abilityFilter over the harvested candidates and prompts the player to pick
--one. Returns nil if there was nothing to offer or the player canceled -- in both
--cases the caller must abort without charging the ability's cost.
--- @param behavior ActivatedAbilityInvokeAbilityBehavior
--- @param casterToken nil|CharacterToken
--- @param options nil|table
--- @return nil|ActivatedAbility
local function ChooseClassAbility(behavior, casterToken, options)
    local candidates = GatherClassAbilities(casterToken)

    local filter = behavior:try_get("abilityFilter", "")
    if filter ~= "" and casterToken ~= nil and casterToken.properties ~= nil then
        local creature = casterToken.properties
        local filtered = {}
        for _,candidate in ipairs(candidates) do
            local symbols = {
                ability = candidate,
                caster = creature,
            }

            if GoblinScriptTrue(ExecuteGoblinScript(filter, creature:LookupSymbol(symbols), 0, "Choose Class Ability Filter")) then
                filtered[#filtered+1] = candidate
            end
        end
        candidates = filtered
    end

    --Two candidates can be the same ability reached by two routes (e.g. a subclass
    --that re-lists a class option). Collapse by name so the list reads cleanly.
    local seen = {}
    local unique = {}
    for _,candidate in ipairs(candidates) do
        local key = string.lower(candidate.name or "")
        if not seen[key] then
            seen[key] = true
            unique[#unique+1] = candidate
        end
    end

    table.sort(unique, function(a,b)
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)

    return ActivatedAbility.ShowAbilityChoiceDialog(unique, {
        title = behavior:try_get("chooseAbilityTitle", "Choose an Ability"),
        buttonText = "Use",
        emptyText = behavior:try_get("chooseAbilityEmptyText", "You have no abilities available to choose from right now."),

        --Right-hand column: where the ability came from and what it costs, so the
        --player can choose without opening every tooltip.
        detailText = function(ability)
            local parts = {}

            local className = ability:try_get("_tmp_className", "")
            local classLevel = ability:try_get("_tmp_classLevel", 0)
            if className ~= "" then
                parts[#parts+1] = string.format("%s %d", className, classLevel)
            end

            local resourceid = ability:try_get("resourceCost", "none")
            if resourceid ~= "none" then
                local resourceInfo = (dmhub.GetTable("characterResources") or {})[resourceid]
                local quantity = tonumber(ability:try_get("resourceNumber", ""))
                if resourceInfo ~= nil and quantity ~= nil and quantity > 0 then
                    parts[#parts+1] = string.format("%d %s", quantity, resourceInfo.name)
                end
            end

            return table.concat(parts, "  -  ")
        end,
    }, casterToken)
end


function ActivatedAbilityInvokeAbilityBehavior:Cast(ability, casterToken, targets, options)

    --Resolve a "choose an ability off your class list" pick up front, before any
    --targeting and before CommitToPaying: backing out of the picker must not spend
    --the invoking ability's cost or burn its usage-limit charge. Hoisted out of the
    --per-target loop below so the dialog is shown once, not once per target.
    local chosenClassAbility = nil
    if self.abilityType == "chooseClassAbility" then
        chosenClassAbility = ChooseClassAbility(self, casterToken, options)
        if chosenClassAbility == nil then
            return
        end
    end

    local promptWhenResolving = self:try_get("promptWhenResolving", false)
    local rangeOrigin = self:try_get("rangeOrigin", "")

    local targetChoices = {}
    if promptWhenResolving then
        for _,target in ipairs(targets or {}) do
            local targetToken = target.token
            targetChoices[#targetChoices+1] = targetToken
        end
    end

    repeat

        --Each pass of this loop resolves the invoke for ONE chosen target when
        --Choose Invocation Order is on. Mark the start of a fresh movement
        --scope on the shared cast so Cast.SpacesMovedThisInvocation reports
        --only this target's movement (e.g. Pack Formation: each wolf's second
        --shift is limited to the remainder of THAT wolf's speed, not starved
        --by the wolves that moved before it). Gated on promptWhenResolving:
        --nested invoke behaviors (the legs of a multi-behavior chain) run this
        --same Cast function and must NOT reset the scope, or a later leg's
        --parameter formulas would always see 0.
        if promptWhenResolving and options.symbols ~= nil and options.symbols.cast ~= nil then
            options.symbols.cast:BeginInvocationMovementScope()
        end

        if promptWhenResolving and #targetChoices > 0 then

            print("INVOKE:: ChooseTarget:: prompting...")
            targets = nil
            GameHud.instance.actionBarPanel:FireEventTree("chooseTargetToken", {
                sourceToken = casterToken,
                targets = table.shallow_copy(targetChoices),
                prompt = self:try_get("promptWhenResolvingText", "Choose Target"),
                choose = function(targetToken)
                    print("ChooseTarget:: chosen")
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
                --If the caster died while we waited, the prompt is gone and
                --no answer will ever come. Treat it as cancelled so the
                --ability can finish instead of hanging.
                if casterToken == nil or not casterToken.valid or casterToken.properties == nil then
                    targets = {}
                    targetChoices = {}
                end
            end
        end


        print("INVOKE:: Casting on", #targets, ability.name, "coroutine:", coroutine.running())
        --TODO: maybe only commit to paying with more generous criteria -- only if an ability
        --is actually used?
        ability:CommitToPaying(casterToken, options)
        for i,target in ipairs(targets) do
            if target.token ~= nil then
                print("INVOKE:: CASTING ON TARGET", i, "/", #targets)

                local rangeOriginTokenId = nil
                if rangeOrigin == "parent_primary_target" then
                    rangeOriginTokenId = GetParentPrimaryTargetTokenId(options)
                elseif rangeOrigin == "parent_current_target" then
                    rangeOriginTokenId = GetParentCurrentTargetTokenId(options, target.token)
                end

                --In a squad coordinated strike, the invoked effect (e.g. a forced-
                --movement push/pull, or an inflicted condition) should be SOURCED
                --from the main minion for THIS creature -- the first minion to
                --attack it -- not from the cast's caster (the squad lead). This
                --mirrors the per-creature attribution applied to power-roll tier
                --commands in MCDMAbilityRollBehavior. Without targetPairs (non-squad
                --invokes) this is just the caster, so behavior is unchanged.
                local invokeSource = casterToken
                if options.symbols ~= nil and options.symbols.cast ~= nil then
                    invokeSource = options.symbols.cast:MainAttackerForTarget(options.symbols, target.token, casterToken)
                end

                --be careful not to put anything in here we don't want to transmit to the database.
                local symbols = { spellname = options.symbols.spellname or ability.name, charges = options.symbols.charges, cast = options.symbols.cast, forcedMovementOrigin = options.symbols.forcedMovementOrigin, forcedMovementOriginTokenId = options.symbols.forcedMovementOriginTokenId }

                --Opt-in only: 'attacker' (and other trigger-only symbols) do not
                --normally cross the invoke boundary, since most invokes have no
                --use for them and they aren't safe to forward unconditionally
                --(e.g. an unrelated "you may shift" reaction on an attacker-based
                --trigger should not have its destination silently restricted).
                --When compelTowardAttacker is set, forward the attacker and set
                --compeltoward so the invoked ability's own empty-space filtering
                --(see ActivatedAbility:TargetLocPassesFilterPredicate) keeps only
                --destinations that move the caster closer to the attacker.
                if self:try_get("compelTowardAttacker", false) and options.symbols.attacker ~= nil then
                    symbols.attacker = options.symbols.attacker
                    symbols.compeltoward = options.symbols.attacker
                end

                --chooseClassAbility is excluded alongside custom: both resolve to an
                --ability object that only exists on this client, so there is nothing
                --the remote controller could look up from a serialized invocation.
                if self.runOnController and target.token.activeControllerId ~= nil and self.abilityType ~= "custom" and self.abilityType ~= "chooseClassAbility" then

                    --Clean out the ability so we don't copy too much, and make the
                    --cast serialization-safe: it holds live objects (targets[].token
                    --CharacterToken userdata; the ability's function fields) which
                    --DeepCopy cannot copy ("Unknown type deep copied" errors) and
                    --which corrupt the target token's properties when the
                    --remoteInvokes write fails to serialize them. SerializeEventValue
                    --converts tokens to string refs, which PumpRemoteInvokes resolves
                    --back to live objects on the controller's machine.
                    local cast = SerializeEventValue(options.symbols.cast)
                    cast.ability = nil
                    symbols.cast = cast

                    local subjectid
                    if options.symbols.subject ~= nil then
                        local s = options.symbols.subject
                        if type(s) == "function" then
                            s = s("self")
                        end

                        subjectid = dmhub.LookupTokenId(s)
                    end


                    --dispatch this to run on the controller.
                    local invocation = AbilityInvocation.new{
                        timestamp = ServerTimestamp(),
                        userid = target.token.activeControllerId,
                        abilityType = self.abilityType,
                        namedAbility = self.namedAbility,
                        standardAbility = self.standardAbility,
                        standardAbilityParams = self:try_get("standardAbilityParams"),
                        targeting = self.targeting,
                        invokerid = invokeSource.id,
                        casterid = cond(self.invokeOnCaster, casterToken.id, target.token.id),
                        targetid = target.token.id,
                        subjectid = subjectid,
                        symbols = symbols,
                        abilityAttr = {
                            promptOverride = cond(self.promptText ~= "", StringInterpolateGoblinScript(self.promptText, casterToken.properties:LookupSymbol{})),
                            disableSquadCoordination = cond(not self:try_get("useSquadCoordination", false), true),
                        }
                    }

                    if rangeOriginTokenId ~= nil then
                        invocation.abilityAttr.rangeOriginTokenId = rangeOriginTokenId
                    end

                    --Held back until the casts currently resolving on this
                    --client complete. This invoke may come from a triggered
                    --reaction activated during the triggering ability's roll
                    --(e.g. In All This Confusion's teleport), and delivering it
                    --mid-cast prompts the remote player to move a token the
                    --local player is still resolving a forced move against.
                    --The timestamp is refreshed at delivery so the deferral
                    --doesn't consume the 30-second staleness window checked by
                    --PumpRemoteInvokes.
                    ActivatedAbility.RunWhenCastsComplete(function()
                        if target.token == nil or not target.token.valid then
                            return
                        end
                        invocation.timestamp = ServerTimestamp()
                        target.token:ModifyProperties{
                            description = "Invoke Ability",
                            undoable = false,
                            execute = function()
                                local invokes = target.token.properties:get_or_add("remoteInvokes", {})
                                invokes[#invokes+1] = DeepCopy(invocation)
                            end,
                        }
                    end)

                else

                    local abilityTemplate = nil
                    if self.abilityType == "named" then
                        local abilities = target.token.properties:GetActivatedAbilities{allLoadouts = true, bindCaster = true}
                        for _,ability in ipairs(abilities) do
                            if string.lower(ability.name) == string.lower(self.namedAbility) then
                                abilityTemplate = ability
                                break
                            end
                        end
                    elseif self.abilityType == "custom" then
                        abilityTemplate = self.customAbility
                    elseif self.abilityType == "standard" then
                        local t = dmhub.GetTable("standardAbilities") or {}
                        abilityTemplate = t[self.standardAbility]
                    elseif self.abilityType == "chooseClassAbility" then
                        --Already chosen at the top of Cast; a nil here means the player
                        --canceled, which returned before we got this far.
                        --
                        --Copied per target: the choice is already a temporary clone, and
                        --MakeTemporaryClone below hands back the same object for one of
                        --those, so without this a second target would re-run the modifier
                        --pipeline over the first target's mutations.
                        abilityTemplate = DeepCopy(chosenClassAbility)
                    end

                    if abilityTemplate ~= nil then
                        local abilityClone = abilityTemplate:MakeTemporaryClone()

                        --The invoked ability is cast through the normal path, which pays
                        --its own action cost as well as the invoking ability's. When the
                        --invoker already charges the action for the whole package, that
                        --double-charge makes the invoked ability unaffordable, so clear it.
                        --Safe to do on the clone: for custom/standard MakeTemporaryClone
                        --returned a fresh copy, and chooseClassAbility DeepCopies per target.
                        if self:try_get("suppressInvokedActionCost", false) then
                            abilityClone.actionResourceId = "none"
                        end

                        --A borrowed class ability must pay its own Heroic Resource -- that
                        --is the whole point of "provided you can spend any required Heroic
                        --Resource". ExecuteInvoke's direct-cast path never sets options.pay,
                        --and heroic abilities mostly report RequiresPromptWhenCast() == false
                        --so they take exactly that path, which would silently skip payment.
                        --Implicit for this mode rather than a flag, so existing invoke
                        --content (overwhelmingly free custom abilities) is untouched.
                        if self.abilityType == "chooseClassAbility" then
                            abilityClone._tmp_payInvokedCost = true
                        end

                        if self.abilityType == "standard" or self.abilityType == "custom" then

                            local allParameters = {}
                            AbilityUtils.ExtractAbilityParameters(abilityClone, allParameters)

                            local symbols = table.union(options.symbols, {
                                target = GenerateSymbols(target.token.properties),
                                invoker = GenerateSymbols(casterToken.properties),
                            })
                            for k,v in pairs(self:try_get("standardAbilityParams", {})) do
                                allParameters[k] = nil
                                local str = AbilityUtils.SubstituteAbilityParameters(v, casterToken.properties:LookupSymbol(symbols))
                                AbilityUtils.DeepReplaceAbility(abilityClone, "<<"..k..">>", str)
                            end
                            for k,_ in pairs(allParameters) do
                                --clear out any parameters we didn't explicitly set.
                                AbilityUtils.SetDefaultParameters(abilityClone, k)
                            end
                        end

                        abilityClone.invoker = ability:try_get("invoker") or casterToken.properties

                        if not self:try_get("useSquadCoordination", false) then
                            abilityClone.disableSquadCoordination = true
                        end

                        if self.inheritRange then
                            abilityClone.range = ability.range
                            abilityClone.rangeUsesInvoker = true
                        end

                        if self:try_get("inheritKeywords", false) then
                            abilityClone.keywords = ability.keywords
                        end

                        --For custom abilities the invoker (the creature actually casting the
                        --invoked ability) doesn't get its modifier pipeline run automatically --
                        --normal abilities go through GetActivatedAbilities which applies modifiers,
                        --but custom invokes use the static template directly. Bifurcate dual-
                        --keyword strikes first so per-variant modifiers land on the right variant,
                        --then run the invoker's modifier pipeline, then call PostProcessInvoked-
                        --Ability for any per-creature-type adjustments that live outside the
                        --modifier system (e.g. AnimalCompanion's melee damage bonus).
                        --chooseClassAbility candidates are harvested raw out of the class
                        --level lists rather than through GetActivatedAbilities, so unlike
                        --"named" they have not been through the modifier pipeline yet. Run
                        --them through it here so a borrowed class ability picks up the
                        --character's kit, feats and other bonuses exactly as it would if
                        --they had actually learned it.
                        if (self.abilityType == "custom" or self.abilityType == "chooseClassAbility") and target.token ~= nil and target.token.properties ~= nil then
                            local invokerCreature = target.token.properties
                            abilityClone = abilityClone:BifurcateIntoMeleeAndRanged(invokerCreature)
                            for _, mod in ipairs(invokerCreature:GetActiveModifiers()) do
                                if abilityClone == nil then break end
                                abilityClone = mod.mod:ModifyAbility(mod, invokerCreature, abilityClone)
                                if abilityClone ~= nil then
                                    local variations = abilityClone:GetVariations()
                                    if variations ~= nil then
                                        for vi = 1, #variations do
                                            mod.mod:ModifyAbility(mod, invokerCreature, variations[vi])
                                        end
                                    end
                                end
                            end
                            if abilityClone ~= nil and invokerCreature.PostProcessInvokedAbility ~= nil then
                                abilityClone = invokerCreature:PostProcessInvokedAbility(abilityClone) or abilityClone
                            end
                        end

                        --When inheritRoll is set, force the invoked ability's power roll(s)
                        --to reuse the parent cast's raw d10 result instead of rolling fresh.
                        --PowerRollBehavior reads this off symbols.forcedroll and substitutes
                        --the dice portion of the formula with the natural value. The child's
                        --own characteristic bonus and any edges/banes/triggers in the dialog
                        --still stack on top.
                        if self:try_get("inheritRoll", false) and options.symbols.cast ~= nil then
                            local parentNatural = options.symbols.cast:try_get("naturalRoll")
                            if parentNatural ~= nil then
                                symbols.forcedroll = parentNatural
                            end
                        end

                        if self.promptText ~= "" then
                            abilityClone.promptOverride = StringInterpolateGoblinScript(self.promptText, casterToken.properties:LookupSymbol{})
                        end

                        -- Apply forced movement bonuses if this is a forced movement ability
                        local forcedMovementType = abilityClone:try_get("forcedMovement")
                        if forcedMovementType ~= nil then
                            local baseMoveType = string.gsub(forcedMovementType, "^vertical_", "")
                            local baseRange = abilityClone:GetRange(casterToken.properties) / dmhub.unitsPerSquare

                            local adjustments = {}
                            local sizeDifferenceBonus = 0
                            local parentKeywords = ability.keywords or {}
                            if parentKeywords["Weapon"] and parentKeywords["Melee"] then
                                local isKnockback = ability:IsKnockbackManeuver()
                                local casterSize = casterToken.properties:CreatureSizeWhenForceMoving(isKnockback)
                                local targetSize = target.token.properties:CreatureSizeWhenBeingForceMoved(isKnockback)
                                if casterSize > targetSize then
                                    sizeDifferenceBonus = 1
                                    adjustments[#adjustments+1] = "Big Versus Little: +1"
                                end
                            end

                            local stability = target.token.properties:Stability()
                            if stability ~= 0 and casterToken.properties:CalculateNamedCustomAttribute("Ignore Stability") > 0 then
                                stability = 0
                                adjustments[#adjustments+1] = "Ignoring Stability"
                            end

                            local forcedMovementIncrease = target.token.properties:CalculateNamedCustomAttribute("Forced Movement Increase")
                            if forcedMovementIncrease > 0 then
                                adjustments[#adjustments+1] = string.format("Forced Movement Increase: +%d", forcedMovementIncrease)
                            end

                            local forcedMovementBonus = casterToken.properties:ForcedMovementBonus(baseMoveType)
                            if forcedMovementBonus > 0 then
                                local describe = casterToken.properties:DescribeForcedMovementBonus(baseMoveType)
                                local textItems = {}
                                for _,entry in ipairs(describe) do
                                    textItems[#textItems+1] = entry.key
                                end
                                if #textItems > 0 then
                                    adjustments[#adjustments+1] = string.format("Forced Movement Bonus (%s): +%d", table.concat(textItems, ", "), forcedMovementBonus)
                                end
                            end

                            local adjustedRange = math.max(0, baseRange - stability + sizeDifferenceBonus + forcedMovementIncrease + forcedMovementBonus)

                            if stability > 0 then
                                adjustments[#adjustments+1] = string.format("Stability: -%d", stability)
                            end

                            abilityClone.range = adjustedRange * dmhub.unitsPerSquare
                            local description = string.format("You may %s the target %d square%s", baseMoveType, adjustedRange, adjustedRange > 1 and "s" or "")
                            if #adjustments > 0 then
                                description = description .. " (" .. table.concat(adjustments, ", ") .. ")"
                            end
                            abilityClone.promptOverride = description
                        end

                        local autoTarget = self:try_get("autoTarget", true)
                        if autoTarget and not abilityClone:RequiresPromptWhenCast() and abilityClone:try_get("promptOverride") == nil then
                            abilityClone.castImmediately = true
                            print("INVOKE:: Auto-target enabled for", abilityClone.name)
                        end

                        if self.targeting == "formula" or self.targeting == "prompt_inherit" then
                            options.targetingFormula = self:try_get("targetingFormula", "")
                        end

                        if rangeOriginTokenId ~= nil then
                            abilityClone.rangeOriginTokenId = rangeOriginTokenId
                        end

                        print("Invoke:: Execute...")
                        --invokeOnCaster: in a squad coordinated strike the "caster" for THIS
                        --target's invoke is the main minion for that creature (invokeSource,
                        --computed above via MainAttackerForTarget), not the cast's lead minion.
                        --Without squad pairing invokeSource IS casterToken, so this is a no-op.
                        --
                        --When the behavior's applyto is "caster" or "caster_including_squad",
                        --ApplyToTargets has already resolved each entry in `targets` to the
                        --caster-side token that should act (the per-unique-target main
                        --attackers, or each squad member). That token IS the intended caster
                        --of the invoke: re-deriving it via MainAttackerForTarget would look
                        --the minion up on the target side of targetPairs, find nothing, and
                        --fall back to the cast lead -- making the lead cast every copy. For
                        --a non-squad caster both values equal casterToken, so this is a
                        --no-op there. Deliberately NOT applied to the other caster_* mappings
                        --(caster_summoner, caster_companion, caster_riders, caster_minions,
                        --caster_and_targets): for those the mapped token is a DIFFERENT
                        --creature than the caster, and invokeOnCaster keeps its meaning of
                        --"the caster casts it, once per mapped creature".
                        local invokerToken
                        if self.invokeOnCaster then
                            if self.applyto == "caster" or self.applyto == "caster_including_squad" then
                                invokerToken = target.token
                            else
                                invokerToken = invokeSource
                            end
                        else
                            invokerToken = target.token
                        end
                        self.ExecuteInvoke(invokeSource, abilityClone, invokerToken, self.targeting, symbols, options)
                    end
                end

            end
        end
    until promptWhenResolving == false or #targetChoices == 0
end

--A string that changes every time the turn changes. Used to spot a leftover flag from
--an invoke that never finished.
function ActivatedAbilityInvokeAbilityBehavior.SquadSuppressionTurnKey()
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return "none"
    end
    return string.format("%s:%s:%s", tostring(q.round), tostring(q.turn), tostring(q.currentTurn))
end

function ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(invokerToken, abilityClone, casterToken, targeting, symbols, options)
    --record if we have to 'pay' for the invoke -- if work was done.
    local haveToPay = false

    options = options or {}

    --When the invoke opted out of squad coordination, mirror the abilityClone flag
    --onto the cast caster's properties as a transient depth counter so any cloned/
    --bifurcated/synthesized variant produced downstream is also covered.
    --UsesSquadCoordination checks both signals.
    local suppressSquad = abilityClone:try_get("disableSquadCoordination", false) == true
    if suppressSquad and casterToken ~= nil and casterToken.properties ~= nil then
        local depth = casterToken.properties:try_get("_tmp_disableSquadCoordinationDepth", 0)
        casterToken.properties._tmp_disableSquadCoordinationDepth = depth + 1
        casterToken.properties._tmp_disableSquadCoordinationTurn = ActivatedAbilityInvokeAbilityBehavior.SquadSuppressionTurnKey()
    end

    --Always lower the counter again on the way out, not just when a cast finishes. If
    --the player declines the prompt it used to stay up, and that minion's squad could
    --never attack with more than one member again (report 3ERZG7SW).
    local squadSuppressionReleased = false
    local ReleaseSquadSuppression = function()
        if squadSuppressionReleased or not suppressSquad then
            return
        end
        squadSuppressionReleased = true
        if casterToken == nil or casterToken.properties == nil then
            return
        end
        local depth = casterToken.properties:try_get("_tmp_disableSquadCoordinationDepth", 0)
        if depth <= 1 then
            casterToken.properties._tmp_disableSquadCoordinationDepth = nil
            casterToken.properties._tmp_disableSquadCoordinationTurn = nil
        else
            casterToken.properties._tmp_disableSquadCoordinationDepth = depth - 1
        end
    end

    print("INVOKE:: STARTING:", abilityClone.name)
    --wait until we aren't casting on the action bar to invoke this. Also resolve
    --any new casts that may have started since we got here.
    local snapshot = ActivatedAbility.GetActiveCastSnapshot()
    while (gamehud.rollDialog.valid and gamehud.rollDialog.data.IsShown()) or (gamehud.actionBarPanel.valid and gamehud.actionBarPanel.data.IsCastingSpell()) or ActivatedAbility.HasCoroutinesNotInSnapshot(snapshot) do
        coroutine.safe_sleep_while(function()
            if not gamehud.actionBarPanel.valid then
                return false
            end
            return gamehud.actionBarPanel.data.IsCastingSpell() or ActivatedAbility.HasCoroutinesNotInSnapshot(snapshot)
        end)

        --give a chance for other casts to continue.
        coroutine.yield()
        coroutine.yield()
    end

        print("INVOKE:: CONTINUE FOR", abilityClone.name, "active casts = ", ActivatedAbility.CountActiveCasts(), "coroutine:", coroutine.running())



	local casting = false

    --Backstop for a cast that begins and never finishes. The action bar can drop
    --a begun cast without ever firing a finish handler -- e.g. the invoke prompt
    --is displaced by the caster activating another ability directly from the
    --ability menu -- which leaves `casting` stuck true and parks this coroutine
    --forever. That zombie used to starve every deferred trigger on the client;
    --FlushCastCompleteActions now evicts a blocker like this after
    --DEFERRED_CAST_ABANDON_SECONDS, so the visible starvation is already
    --contained and this cap only has to stop the coroutine leaking for the rest
    --of the session. Deliberately far longer than any real prompt interaction:
    --it must never cut off a player who is just taking their time deciding.
    local INVOKE_WAIT_TIMEOUT_SECONDS = 300

	symbols.invoker = symbols.invoker or GenerateSymbols(invokerToken.properties)
    local invoker = symbols.invoker
    if type(invoker) == "function" then
        invoker = invoker("self")
    end

	abilityClone.invoker = invokerToken.properties

	local OnBeginCast = abilityClone:try_get("OnBeginCast")
	local OnFinishCast = abilityClone:try_get("OnFinishCast")

    local finishedCasting = false

    --The finish-side signaling must live on options.OnFinishCastHandlers rather than
    --ability.OnFinishCast: the engine's cast-time serialization strips function-valued
    --fields from the ability during long casts (e.g. a power roll dialog). Handlers
    --on the options table are not touched by that pass.
    local finishHandler = function(ability, _, finishOptions)
        if finishedCasting then return end
        if OnFinishCast then
            OnFinishCast(ability, finishOptions)
        end
        casting = false
        finishedCasting = true
        ReleaseSquadSuppression()
        if finishOptions.pay then
            --if the ability we invoked had to be paid for, we have to pay for the invoke.
            ability:CommitToPaying(casterToken, finishOptions)
            haveToPay = true --we'll return that we 'did work' and have to pay.
        end
    end

    local installFinishHandler = function(castOptions)
        if castOptions == nil then return end
        castOptions.OnFinishCastHandlers = castOptions.OnFinishCastHandlers or {}
        castOptions.OnFinishCastHandlers[#castOptions.OnFinishCastHandlers + 1] = finishHandler
    end

    --Prompt handlers can replace a wrapper ability with a concrete synthesized
    --ability (for example, choosing Melee Free Strike from the generic Free
    --Strike prompt). Every replacement still needs the invoke lifecycle hooks.
    local installCastCallbacks = function(castAbility)
        local priorBeginCast = castAbility:try_get("OnBeginCast")
        local priorFinishCast = castAbility:try_get("OnFinishCast")

        castAbility.OnBeginCast = function(beginAbility, castOptions)
            if priorBeginCast then
                priorBeginCast(beginAbility, castOptions)
            end
            casting = true
            installFinishHandler(castOptions)
        end

        --Defense-in-depth: keep OnFinishCast as a fallback in case this path
        --somehow runs through a Cast that skips OnBeginCast. finishHandler is
        --idempotent via finishedCasting.
        castAbility.OnFinishCast = function(finishedAbility, finishOptions)
            if priorFinishCast then
                priorFinishCast(finishedAbility, finishOptions)
            end
            finishHandler(finishedAbility, casterToken, finishOptions)
        end
    end

    installCastCallbacks(abilityClone)

    local canceled = false

    while not finishedCasting do
        --The invoker can be deleted/despawned across the yields in this loop (prompt
        --waits, nested casts): the token reference survives but .valid is false and
        --.properties is nil. Every line below reads invokerToken.properties (AI control
        --flags, prompt callback, symbols), so a gone invoker means there is nothing left
        --to invoke -- end the invoke the same way a direct cancel does (break below).
        if invokerToken == nil or not invokerToken.valid or invokerToken.properties == nil then
            break
        end

        local castCount = 0

        local invokerCallback = {
            oncast = function()
                castCount = castCount + 1
            end,
            oncancel = function()
                canceled = true
            end,
        }

        print("AI:: PUSH:: IN INVOKE token", creature.GetTokenDescription(invokerToken), "targeting =", targeting, "ai", invokerToken.properties._tmp_aicontrol, "promptCallback =", invokerToken.properties._tmp_aipromptCallback, "for", abilityClone.name, coroutine.running())
        --Set when an AI prompt callback answered the prompt: the targets are already
        --resolved, so the cast below must NOT be routed through the action bar UI
        --(which would wait for player clicks that will never come).
        local aiResolvedTargeting = false
        if (targeting == "prompt" or targeting == "prompt_inherit") and invokerToken.properties._tmp_aicontrol > 0 and invokerToken.properties._tmp_aipromptCallback then
            print("PUSH:: INVOKING!!!!!")
            targeting = invokerToken.properties._tmp_aipromptCallback(invokerToken, casterToken, abilityClone, symbols, options)
            aiResolvedTargeting = (targeting ~= "prompt" and targeting ~= "prompt_inherit")
        end

        --A prompt handler may resolve a synthesized-ability chooser as well as
        --its targets. Consume the override immediately so it cannot leak into a
        --later invoke that shares the parent cast's options table.
        local abilityOverride = options.abilityOverride
        if abilityOverride ~= nil then
            options.abilityOverride = nil
            abilityClone = abilityOverride
            abilityClone.invoker = invokerToken.properties
            installCastCallbacks(abilityClone)
        end

        if targeting == "prompt" or targeting == "prompt_inherit" then
            print("INVOKE:: PROMPT CAST FOR", abilityClone.name, coroutine.running())
            abilityClone.countsAsCast = true
            abilityClone.skippable = true

            if targeting == "prompt_inherit" then
                local allowedtargets = {}
                local inheritedTargets = options.targets or {}
                --Optional subset filter: a GoblinScript formula evaluated per
                --inherited target. Targets that fail are excluded so the player
                --can only pick from the filtered subset. Sees Target and Caster;
                --PassesPotency is a creature function, so a formula like
                --Target.PassesPotency("M", Caster.Average) works with no ability.
                local subsetFilter = options.targetingFormula
                for _, target in ipairs(inheritedTargets) do
                    if target.token ~= nil then
                        local passesFilter = true
                        if subsetFilter ~= nil and trim(subsetFilter) ~= "" then
                            local filterSymbols = {
                                target = GenerateSymbols(target.token.properties),
                                caster = GenerateSymbols(casterToken.properties),
                            }
                            passesFilter = GoblinScriptTrue(ExecuteGoblinScript(subsetFilter, invokerToken.properties:LookupSymbol(filterSymbols), 0, "Invoke Subset Filter"))
                        end
                        if passesFilter then
                            allowedtargets[target.token.charid] = true
                        end
                    end
                end
                symbols.allowedtargets = allowedtargets
            end

            gamehud.actionBarPanel:FireEventTree("invokeAbility", casterToken, abilityClone, symbols, invokerCallback)
        else
            abilityClone.countsAsCast = options.countsAsCast or false
            local targets
            if targeting == "self" then
                targets = { { token = casterToken } }
            elseif targeting == "inherit" then
                targets = options.targets or {}
                --Lock target selection to exactly the inherited targets -- the player
                --should not be able to swap in different targets for an "inherit"
                --invoke, since the whole point is to reuse the parent ability's targets.
                local allowedtargets = {}
                for _, target in ipairs(targets) do
                    if target.token ~= nil then
                        allowedtargets[target.token.charid] = true
                    end
                end
                symbols.allowedtargets = allowedtargets
            elseif targeting == "args" then
                targets = options.targetArgs or {}
            elseif targeting == "formula" then
                targets = {}
                local allTokens = dmhub.allTokens
                local symbols = table.shallow_copy(options.symbols)
                symbols.invoker = invokerToken.properties
                symbols.caster = casterToken.properties

                for _,token in ipairs(allTokens) do
                    symbols.target = token.properties
                    if GoblinScriptTrue(ExecuteGoblinScript(options.targetingFormula, invokerToken.properties:LookupSymbol(symbols), 0)) then
                        targets[#targets+1] = { token = token }
                    end
                end
            end

            if abilityClone:RequiresPromptWhenCast() then
                local synth = abilityClone:SynthesizeAbilities(casterToken.properties)
                if synth ~= nil and #synth == 1 then
                    --if exactly one synthesized ability then just auto-cast it?
                    local preSynthDisableSquad = abilityClone:try_get("disableSquadCoordination")
                    abilityClone = synth[1]
                    --Synthesizing builds a fresh ability, so copy the opt-out across.
                    --Without it a minion gets asked for one target per squad member.
                    if preSynthDisableSquad ~= nil then
                        abilityClone.disableSquadCoordination = preSynthDisableSquad
                    end
                    --The synth is a brand-new ability; re-install our wrappers
                    --while preserving any callbacks the synth came with.
                    installCastCallbacks(abilityClone)
                end
            end

            if (not aiResolvedTargeting) and (abilityClone:RequiresPromptWhenCast() or abilityClone:try_get("promptOverride") ~= nil) then
                abilityClone.skippable = true
                gamehud.actionBarPanel:FireEventTree("invokeAbility", casterToken, abilityClone, symbols, invokerCallback, {instantCast = true, targets = targets})
            else
                --Immediate cast: we control the options table so just pre-install the finish handler.
                --pay defaults to false (the historical behavior for invoked abilities, which are
                --almost always free custom abilities); callers that invoke a REAL costed ability
                --stamp _tmp_payInvokedCost so its own resource cost is actually charged.
                --The selected area is cast state and must survive this invoke boundary.
                local castOptions = {
                    symbols = symbols,
                    targetArea = options.targetArea,
                    targetAreaList = options.targetAreaList,
                    pay = abilityClone:try_get("_tmp_payInvokedCost", false),
                    OnFinishCastHandlers = { finishHandler },
                }
                abilityClone:Cast(casterToken, targets, castOptions)
            end
        end

        local lastWaitDiag = 0
        local waitStarted = dmhub.Time()
        local timedOut = false
        coroutine.safe_sleep_while(function()

            local isCasting = casting
            if not gamehud.actionBarPanel.valid then
                return false
            end
            local isPreparing = gamehud.actionBarPanel.data.IsCastingSpell()

            --DIAG: heartbeat while an invoke waits on its prompt/cast so a
            --"hung" session's log shows what it is waiting on. Safe to keep.
            local now = dmhub.Time()
            if now - lastWaitDiag > 5 then
                lastWaitDiag = now
                print(string.format("INVOKEDIAG:: waiting for %s casting=%s preparing=%s T=%.2f",
                    tostring(abilityClone.name), tostring(isCasting),
                    tostring(isPreparing ~= false and isPreparing ~= nil), now))
            end

            if (isCasting or isPreparing) and now - waitStarted > INVOKE_WAIT_TIMEOUT_SECONDS then
                printf("INVOKEDIAG:: giving up on %s after %ds (casting=%s preparing=%s) -- treating the invoke as cancelled",
                    tostring(abilityClone.name), math.floor(now - waitStarted),
                    tostring(isCasting), tostring(isPreparing ~= false and isPreparing ~= nil))
                timedOut = true
                casting = false
                return false
            end

            return isCasting or isPreparing
        end)

        if timedOut then
            --Unwind the same way a cancel does rather than re-prompting.
            canceled = true
            break
        end

        if castCount <= 1 then
            --this looks like a direct cancel out of casting so we just break out.
            break
        end
    end

    --Catches the cases where no cast ever finished, such as the player declining.
    ReleaseSquadSuppression()

    print("INVOKE:: FINISHED FOR", abilityClone.name, coroutine.running(), "CANCELED:", canceled)

    return haveToPay
end

ActivatedAbilityInvokeAbilityBehavior.abilityType = "custom"
ActivatedAbilityInvokeAbilityBehavior.namedAbility = ""
ActivatedAbilityInvokeAbilityBehavior.standardAbility = ""

--Used only when abilityType is "chooseClassAbility". GoblinScript run over every
--ability offered by the caster's class/subclass level lists; those it returns true for
--are offered to the player.
ActivatedAbilityInvokeAbilityBehavior.abilityFilter = ""
ActivatedAbilityInvokeAbilityBehavior.chooseAbilityTitle = "Choose an Ability"
ActivatedAbilityInvokeAbilityBehavior.chooseAbilityEmptyText = "You have no abilities available to choose from right now."

--Set when the invoking ability already charges the action cost for the whole package,
--so the invoked ability should not charge its own on top.
ActivatedAbilityInvokeAbilityBehavior.suppressInvokedActionCost = false
ActivatedAbilityInvokeAbilityBehavior.targeting = "prompt"
ActivatedAbilityInvokeAbilityBehavior.inheritRange = false

function ActivatedAbilityInvokeAbilityBehavior:EditorItems(parentPanel)

	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Check{
        text = "Choose Invocation Order",
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
                text = "Prompt Order:",
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

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Prompt Text:",
		},
		gui.Input{
			classes = {"formInput"},
			text = self.promptText,
            multiline = true,
            width = 300,
            height = "auto",
            maxHeight = 140,
			change = function(element)
				self.promptText = element.text
			end,
		}
	}

	-- Type row uses the stacked-label default (label above, controls
	-- below) like the other form rows. The dropdown + Edit Ability
	-- button share a horizontal sub-panel on the second line so the
	-- button sits immediately next to the dropdown (only visible when
	-- "Custom Ability" is selected). Same pattern as the Apply Ongoing
	-- Effect behavior's Edit Effect button.
	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Type:",
		},
		gui.Panel{
			width = "auto",
			height = "auto",
			flow = "horizontal",
			halign = "left",
			valign = "center",
			gui.Dropdown{
				options = {
					{ text = "Custom Ability", id = "custom" },
					{ text = "Named Ability", id = "named" },
					{ text = "Choose Class Ability", id = "chooseClassAbility" },
					cond(dmhub.GetTable("standardAbilities") ~= nil, { text = "Standard Ability", id = "standard" } ),
				},
				idChosen = self.abilityType,
				change = function(element)
					self.abilityType = element.idChosen
					parentPanel:FireEventTree("refreshInvoke")
				end,
			},

			gui.Button{
				classes = {cond(self.abilityType ~= "custom", "collapsed-anim")},
				width = "auto",
				height = 28,
				halign = "left",
				lmargin = 8,
				fontSize = 16,
				text = "Edit Ability",
				refreshInvoke = function(element)
					element:SetClass("collapsed-anim", self.abilityType ~= "custom")
				end,
				click = function(element)
					element.root:AddChild(self.customAbility:ShowEditActivatedAbilityDialog())
				end,
			},
		},
	}

	result[#result+1] = gui.Panel{
		classes = {"formPanel", cond(self.abilityType ~= "chooseClassAbility", "collapsed")},
		refreshInvoke = function(element)
			element:SetClass("collapsed", self.abilityType ~= "chooseClassAbility")
		end,
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
				help = "This GoblinScript is run over every ability offered by the level lists of the caster's classes, subclasses and domains. Abilities it returns true for are offered to the player to choose from; the chosen one is then cast immediately, paying its own costs. Leave empty to offer every class ability.",
				output = "boolean",
				subject = creature.helpSymbols,
				subjectDescription = "The creature choosing an ability",
				symbols = {
					ability = {
						name = "Ability",
						type = "ability",
						desc = "The class ability being considered. Ability.Class Level, Ability.Levels Above, Ability.Class, Ability.Known and Ability.Prerequisites Met describe where it came from.",
						examples = {
							'Ability.Levels Above = 1 and Ability.Categorization = "Heroic Ability"',
							'Ability.Class is "Tactician"',
							"not Ability.Known",
						},
					},
					caster = {
						name = "Caster",
						type = "creature",
						desc = "The creature choosing an ability.",
						examples = {
							"Caster.Level > 5",
						},
					},
				}
			}
		}
	}

	result[#result+1] = gui.Panel{
		classes = {"formPanel", cond(self.abilityType ~= "chooseClassAbility", "collapsed")},
		refreshInvoke = function(element)
			element:SetClass("collapsed", self.abilityType ~= "chooseClassAbility")
		end,
		gui.Label{
			classes = {"formLabel"},
			text = "Chooser Title:",
		},
		gui.Input{
			classes = {"formInput"},
			text = self:try_get("chooseAbilityTitle", "Choose an Ability"),
			placeholderText = "Choose an Ability",
			characterLimit = 120,
			change = function(element)
				self.chooseAbilityTitle = element.text
			end,
		},
	}

	result[#result+1] = gui.Panel{
		classes = {"formPanel", cond(self.abilityType ~= "chooseClassAbility", "collapsed")},
		refreshInvoke = function(element)
			element:SetClass("collapsed", self.abilityType ~= "chooseClassAbility")
		end,
		gui.Label{
			classes = {"formLabel"},
			text = "No Options Text:",
		},
		gui.Input{
			classes = {"formInput"},
			text = self:try_get("chooseAbilityEmptyText", ""),
			placeholderText = "You have no abilities available to choose from right now.",
			characterLimit = 240,
			change = function(element)
				self.chooseAbilityEmptyText = element.text
			end,
		},
	}

	result[#result+1] = gui.Check{
		text = "Invoked Ability Costs No Action",
		value = self:try_get("suppressInvokedActionCost", false),
		change = function(element)
			self.suppressInvokedActionCost = element.value
		end,
	}

	result[#result+1] = gui.Check{
		text = "Invoke on Caster Token",
		value = self.invokeOnCaster,
		change = function(element)
			self.invokeOnCaster = element.value
		end,
	}

	result[#result+1] = gui.Check{
		classes = {cond(self.abilityType == "custom", "collapsed-anim")},
		text = "Target Player Casts",
		value = self.runOnController,
		change = function(element)
			self.runOnController = element.value
		end,
		refreshInvoke = function(element)
			element:SetClass("collapsed-anim", self.abilityType == "custom")
		end,
	}

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		create = function(element)
			element:SetClass("collapsed", self.abilityType ~= "named")
		end,
		refreshInvoke = function(element)
			element:FireEventTree("create")
		end,
		gui.Label{
			classes = {"formLabel"},
			text = "Ability Name:",
		},
		gui.Input{
			classes = {"formInput"},
			text = self.namedAbility,
			change = function(element)
				self.namedAbility = element.text
			end,
		},
	}

	local standardAbilities = {}
	for k,v in unhidden_pairs(dmhub.GetTable("standardAbilities") or {}) do
		--Abilities marked Hidden are internal helpers and are kept out of this list,
		--except when one is already the current selection.
		if (not v:try_get("hiddenFromInvoke", false)) or k == self.standardAbility then
			--A nameless standardAbilities row would put a nil into the dropdown's
			--sort comparator and stop the menu from opening at all.
			local abilityName = v.name
			if type(abilityName) ~= "string" or abilityName == "" then
				abilityName = "(Unnamed)"
			end
			standardAbilities[#standardAbilities+1] = { text = abilityName, id = k }
		end
	end

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		create = function(element)
			element:SetClass("collapsed", self.abilityType ~= "standard")
		end,
		refreshInvoke = function(element)
			element:FireEventTree("create")
		end,
		gui.Label{
			classes = {"formLabel"},
			text = "Ability:",
		},
		gui.Dropdown{
			sort = true,
			idChosen = self.standardAbility,
			options = standardAbilities,
            hasSearch = true,
			change = function(element)
				self.standardAbility = element.idChosen
				parentPanel:FireEventTree("refreshInvoke")
			end,
		},
	}

	result[#result+1] = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		data = {
			abilityTypeCached = nil,
		},
		create = function(element)
			element:SetClass("collapsed", self.abilityType == "named")

			if self.abilityType == "named" or element.data.abilityTypeCached == self.standardAbility then
				element.children = {}
				return
			end

			element.data.abilityTypeCached = self.standardAbility

            local abilityTemplate

            if self.abilityType == "standard" then
			    local t = dmhub.GetTable("standardAbilities") or {}
			    abilityTemplate = t[self.standardAbility]
            else
                abilityTemplate = self.customAbility
            end

			if abilityTemplate == nil then
				print("Error: Could not find ability template:", self.standardAbility)
				return
			end

			local parameters = {}
			AbilityUtils.ExtractAbilityParameters(abilityTemplate, parameters)
            print("EXTRACT::", parameters)

			local children = {}

			for k,v in pairs(parameters) do
				children[#children+1] = gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						text = k,
					},
					gui.Input{
						classes = {"formInput"},
                        width = 280,
						text = self:try_get("standardAbilityParams", {})[k] or v.defaultValue,
						change = function(element)
							local t = self:get_or_add("standardAbilityParams", {})
							t[k] = element.text
						end,
					},
				}
			end

			element.children = children
		end,
		refreshInvoke = function(element)
			element:FireEventTree("create")
		end,
	}

    local targetingFormulaPanel

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Targeting:",
		},
		gui.Dropdown{
            classes = {"formDropdown"},
			options = {
				{ text = "Prompt Player", id = "prompt" },
				{ text = "Prompt Player (Inherit)", id = "prompt_inherit" },
				{ text = "Self", id = "self" },
                { text = "Inherit From This Ability", id = "inherit"},
                { text = "Creatures Matching Formula", id = "formula"},
			},
			idChosen = self.targeting,
			change = function(element)
				self.targeting = element.idChosen
                targetingFormulaPanel:FireEvent("refreshTargeting")
			end,
		}
	}

    targetingFormulaPanel = gui.Panel{
        classes = {"formPanel"},
        create = function(element)
            element:SetClass("collapsed", self.targeting ~= "formula" and self.targeting ~= "prompt_inherit")
        end,
        refreshTargeting = function(element)
            element:FireEventTree("create")
        end,
        gui.Label{
            classes = {"formLabel"},
            text = "Targeting Formula:",
            create = function(element)
                element.text = cond(self.targeting == "prompt_inherit", "Subset Filter:", "Targeting Formula:")
            end,
        },
        gui.GoblinScriptInput{
            classes = {"formInput"},
            value = self:try_get("targetingFormula", ""),
            change = function(element)
                self.targetingFormula = element.value
            end,
            documentation = {
                help = "For 'Creatures Matching Formula' targeting, selects which creatures are targeted. For 'Prompt Player (Inherit)' targeting, an optional filter narrowing the inherited target subset -- leave blank for no filter. Sees Target and Caster; e.g. Target.PassesPotency(\"M\", Caster.Average).",
                output = "boolean",
                subject = creature.helpSymbols,
				subjectDescription = "The creature invoking the ability",
                examples = {},
                symbols = {
                    target = {name = "Target", type = "creature", desc = "The candidate target of the ability"},
                    caster = {name = "Caster", type = "creature", desc = "The creature casting the invoked ability."},
                    invoker = {name = "Invoker", type = "creature", desc = "The creature invoking the ability. The same as Self."},
                }
            }
        },
    }

    result[#result+1] = targetingFormulaPanel

    result[#result+1] = gui.Check{
        text = "Auto-select targets when possible",
        value = self:try_get("autoTarget", true),
        change = function(element)
            self.autoTarget = element.value
        end,
    }

	result[#result+1] = gui.Check{
		text = "Inherit Range",
		value = self.inheritRange,
		change = function(element)
			self.inheritRange = element.value
		end,
	}

	result[#result+1] = gui.Check{
		text = "Inherit Keywords",
		value = self:try_get("inheritKeywords", false),
		change = function(element)
			self.inheritKeywords = element.value
		end,
	}

	result[#result+1] = gui.Check{
		text = "Use Squad Coordination",
		value = self:try_get("useSquadCoordination", false),
		change = function(element)
			self.useSquadCoordination = element.value
		end,
	}

	result[#result+1] = gui.Check{
		text = "Compel Destination Toward Attacker",
		value = self:try_get("compelTowardAttacker", false),
		change = function(element)
			self.compelTowardAttacker = element.value
		end,
	}

	return result

end

AbilityInvocation.timestamp = 0
AbilityInvocation.abilityType = "named"
AbilityInvocation.abilityid = "none"
AbilityInvocation.targeting = "prompt"
AbilityInvocation.targetingFormula = ""
AbilityInvocation.invokerid = "none"
AbilityInvocation.casterid = "none"

--must be executed from within a co-routine.
function AbilityInvocation:Invoke()
	local invokerToken = dmhub.GetTokenById(self.invokerid)
	local casterToken = dmhub.GetTokenById(self.casterid)

	if invokerToken == nil or casterToken == nil then
		return false
	end

    if self:has_key("subjectid") then
        local subjectToken = dmhub.GetTokenById(self.subjectid)
        if subjectToken ~= nil then
            self.symbols.subject = GenerateSymbols(subjectToken.properties)
        end
    end

	local abilityTemplate = nil
	if self.abilityType == "named" then
		local abilities = casterToken.properties:GetActivatedAbilities{allLoadouts = true, bindCaster = true}
		for _,ability in ipairs(abilities) do
			if string.lower(ability.name) == string.lower(self.namedAbility) then
				abilityTemplate = ability
				break
			end
		end
	elseif self.abilityType == "standard" then
        abilityTemplate = MCDMUtils.GetStandardAbility(self.standardAbility)
	end

	if abilityTemplate == nil then
		return false
	end

	local abilityClone = abilityTemplate:MakeTemporaryClone()
	if self.abilityType == "standard" or self.abilityType == "custom" then
        local lookupSymbols = table.shallow_copy(self.symbols)
        if self:has_key("targetid") then
            local targetToken = dmhub.GetTokenById(self.targetid)
            if targetToken ~= nil then
                lookupSymbols.target = GenerateSymbols(targetToken.properties)
            end
        end

		local allParameters = {}
		AbilityUtils.ExtractAbilityParameters(abilityClone, allParameters)

        lookupSymbols = invokerToken.properties:LookupSymbol(lookupSymbols)
		for k,v in pairs(self:try_get("standardAbilityParams", {})) do
            allParameters[k] = nil
			local str = AbilityUtils.SubstituteAbilityParameters(v, lookupSymbols)
			AbilityUtils.DeepReplaceAbility(abilityClone, "<<"..k..">>", str)
		end

        for k,_ in pairs(allParameters) do
            --clear out any parameters we didn't explicitly set.
            AbilityUtils.SetDefaultParameters(abilityClone, k)
        end
	end

	for k,v in pairs(self:try_get("abilityAttr", {})) do
		abilityClone[k] = v
	end

	-- Apply forced movement bonuses if this is a forced movement ability
	local forcedMovementType = abilityClone:try_get("forcedMovement")
	if forcedMovementType ~= nil then
		-- In remote invocations, invokerToken is the pusher and casterToken is the target being moved
		local pusherToken = invokerToken
		local targetToken = casterToken

		local baseMoveType = string.gsub(forcedMovementType, "^vertical_", "")
		local baseRange = abilityClone:GetRange(pusherToken.properties) / dmhub.unitsPerSquare

		local adjustments = {}
		local sizeDifferenceBonus = 0
		-- Big Versus Little check

		local stability = targetToken.properties:Stability()
		if stability ~= 0 and pusherToken.properties:CalculateNamedCustomAttribute("Ignore Stability") > 0 then
			stability = 0
			adjustments[#adjustments+1] = "Ignoring Stability"
		end

		local forcedMovementIncrease = targetToken.properties:CalculateNamedCustomAttribute("Forced Movement Increase")
		if forcedMovementIncrease > 0 then
			adjustments[#adjustments+1] = string.format("Forced Movement Increase: +%d", forcedMovementIncrease)
		end

		local forcedMovementBonus = pusherToken.properties:ForcedMovementBonus(baseMoveType)
		if forcedMovementBonus > 0 then
			local describe = pusherToken.properties:DescribeForcedMovementBonus(baseMoveType)
			local textItems = {}
			for _,entry in ipairs(describe) do
				textItems[#textItems+1] = entry.key
			end
			if #textItems > 0 then
				adjustments[#adjustments+1] = string.format("Forced Movement Bonus (%s): +%d", table.concat(textItems, ", "), forcedMovementBonus)
			end
		end

		local adjustedRange = math.max(0, baseRange - stability + sizeDifferenceBonus + forcedMovementIncrease + forcedMovementBonus)

		if stability > 0 then
			adjustments[#adjustments+1] = string.format("Stability: -%d", stability)
		end

		abilityClone.range = adjustedRange * dmhub.unitsPerSquare
		local description = string.format("You may %s the target %d square%s", baseMoveType, adjustedRange, adjustedRange > 1 and "s" or "")
		if #adjustments > 0 then
			description = description .. " (" .. table.concat(adjustments, ", ") .. ")"
		end
		abilityClone.promptOverride = description
	end

	local options = {
        targetingFormula = self.targetingFormula,
    }
	ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(invokerToken, abilityClone, casterToken, self.targeting, self.symbols, options)
	return true
end

--Post a prompt card on a creature's trigger panel offering to cast a standard
--ability. The card is stored in the creature's properties (availableTriggers),
--so it syncs to and renders on whichever client controls the creature --
--local or remote -- styled like any other trigger prompt, with Activate and
--Dismiss buttons. Dismissing clears the card and nothing happens. Accepting
--casts the standard ability with the creature as caster ON THE ACCEPTING
--CLIENT, through the same pipeline as the Invoke Ability behavior: <<param>>
--markers in the ability are substituted from args.params (each value is
--interpolated/evaluated as GoblinScript against the invoker, with args.symbols
--available, AT ACCEPT TIME -- pre-evaluate values yourself if you need
--dispatch-time snapshots), and parameters not in args.params fall back to
--their <<param=default>> defaults.
--
--Must be called from a client with authority to modify the token. Two users
--accepting the same card near-simultaneously on different clients is resolved
--by the clear-then-execute in ActivateInvocationPrompt once the clear
--replicates; the deferral in DispatchAvailableTrigger keeps that window small.
--
--args:
--  token            CharacterToken (required). The creature that will cast.
--  standardAbility  string (required). Standard ability id or name.
--  invoker          CharacterToken (optional). Creature credited as invoking
--                   the ability: the subject for parameter substitution, the
--                   invoked ability's invoker, and the portrait shown on the
--                   card. Defaults to token. If the invoker is deleted while
--                   the card is pending, the card is cleared (Invoke cannot
--                   run without a live invoker anyway).
--  params           table<string,string> (optional). <<param>> substitutions.
--  symbols          table (optional). Extra symbols visible to parameter
--                   substitution and the cast. Tokens/creatures (including
--                   GenerateSymbols wrappers) are converted to string refs and
--                   resolved back to live objects on the accepting client.
--  prompt           string (optional). Title of the card. Defaults to the
--                   ability's name.
--  rules            string (optional). Rules/body text shown on the card.
--  activateText     string (optional). Label of the accept button. Defaults
--                   to "Activate".
--  castPrompt       string (optional). promptOverride shown while resolving
--                   the accepted cast.
--  targeting        string (optional). "prompt" (default): the accepting
--                   player targets the ability normally. "self": cast on the
--                   creature itself. "formula": target creatures matching
--                   args.targetingFormula.
--  targetingFormula string (optional). GoblinScript for targeting "formula".
--  hostile          boolean (optional). Styles the card as a hostile prompt
--                   and makes it persist until resolved instead of aging out
--                   after ~600 seconds.
--  free             boolean (optional, default true). false uses the non-free
--                   (gold) trigger styling instead of the free (blue) one.
--
--Returns the prompt's trigger id (its key in availableTriggers, usable to
--watch for resolution), or nil if the ability doesn't exist or the token is
--invalid.
function AbilityInvocation.PromptStandardAbility(args)
    local token = args.token
    if token == nil or (not token.valid) or token.properties == nil then
        printf("PromptStandardAbility: invalid token")
        return nil
    end

    local invokerToken = args.invoker or token

    local abilityTemplate = MCDMUtils.GetStandardAbility(args.standardAbility)
    if abilityTemplate == nil then
        printf("PromptStandardAbility: unknown standard ability: %s", tostring(args.standardAbility))
        return nil
    end

    --Make the symbols serialization-safe, unwrapping GenerateSymbols function
    --wrappers to their underlying creatures the same way trigger prompts do
    --(see SerializeTriggerContext in TriggeredAbility.lua). The card lives in
    --the creature's properties, so live objects must not leak into it.
    local serializedSymbols = {}
    local visited = {}
    for k,v in pairs(args.symbols or {}) do
        if type(v) == "function" then
            local unwrapped = nil
            pcall(function() unwrapped = v("self") end)
            v = unwrapped
        end
        serializedSymbols[k] = SerializeEventValue(v, visited)
    end

    local abilityAttr = {
        disableSquadCoordination = true,
    }
    if args.castPrompt ~= nil and args.castPrompt ~= "" then
        abilityAttr.promptOverride = args.castPrompt
    end

    local invocation = AbilityInvocation.new{
        timestamp = ServerTimestamp(),
        abilityType = "standard",
        standardAbility = args.standardAbility,
        standardAbilityParams = args.params,
        targeting = args.targeting or "prompt",
        targetingFormula = args.targetingFormula or "",
        invokerid = invokerToken.id,
        casterid = token.id,
        targetid = token.id,
        symbols = serializedSymbols,
        abilityAttr = abilityAttr,
    }

    --Show who is prompting on the card when the invoker is a different
    --creature. Listing the invoker in targets also means the card clears if
    --the invoker is deleted (see creature:OnTokenDelete).
    local cardTargets = {}
    if invokerToken.charid ~= token.charid then
        cardTargets[#cardTargets+1] = invokerToken.charid
    end

    local trigger = ActiveTrigger.new{
        id = dmhub.GenerateGuid(),
        text = args.prompt or abilityTemplate.name,
        rules = args.rules or "",
        activateText = args.activateText or "Activate",
        targets = cardTargets,
        clearOnDismiss = true,
        noDeduplicate = true,
        free = args.free ~= false,
        hostile = args.hostile == true,
        invocation = invocation,
    }

    local triggerid = trigger.id

    token:ModifyProperties{
        description = "Ability Prompt",
        undoable = false,
        execute = function()
            token.properties:DispatchAvailableTrigger(trigger)
        end,
    }

    return triggerid
end

--Consume an accepted invocation prompt. Scheduled (deferred ~0.25s) from
--creature:DispatchAvailableTrigger on the client that recorded the
--acceptance -- normally the player controlling the creature, or the Director
--accepting on their behalf. Re-reads the live record (the acceptance can be
--toggled off before the deferral fires), clears the card FIRST -- mirroring
--ActivateOrphanedTrigger's clear-then-execute order, so a record that fails
--to run goes away rather than staying clickable -- then deserializes and runs
--the invocation through the same pipeline PumpRemoteInvokes uses for
--remoteInvokes records.
function AbilityInvocation.ActivateInvocationPrompt(casterToken, triggerid)
    if casterToken == nil or (not casterToken.valid) or casterToken.properties == nil then
        return
    end

    local availableTriggers = casterToken.properties:try_get("availableTriggers")
    local record = availableTriggers ~= nil and availableTriggers[triggerid] or nil
    if record == nil then
        --already consumed.
        return
    end

    if record.triggered == false or record.dismissed then
        return
    end

    local invocation = record.invocation
    if invocation == false or invocation == nil then
        return
    end

    casterToken:ModifyProperties{
        description = "Clear Ability Prompt",
        undoable = false,
        execute = function()
            casterToken.properties:ClearAvailableTrigger({id = triggerid})
        end,
    }

    --Resolve "charid:"/"tokenid:" refs in the stored record back to live
    --objects, the same way PumpRemoteInvokes does for remote invocations.
    local invoke = DeserializeEventValue(DeepCopy(invocation))

    dmhub.Coroutine(function()
        invoke:Invoke()
    end)
end
