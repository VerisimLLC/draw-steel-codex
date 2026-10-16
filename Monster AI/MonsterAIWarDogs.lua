local mod = dmhub.GetModLoading()

--Monster AI for the War Dog band, echelon 1 (levels 1-3): the Commando,
--Conscript, Sharpshooter and Tetherite minions, the Amalgamite, Crucibite,
--Eviscerite, Neuronite, Pestilite, Phosphorite, Teletalite and Subcommander,
--the Ground Commander leader, and the band's level 1+ Malice features
--(Reconstitute, Fire for Effect, Fodder Run).
--
--Minion signature strikes are coordinated by the shared squad logic. What
--makes war dogs war dogs is the loyalty collar: every war dog explodes when it
--is reduced to 0 Stamina, and their captains treat minions as ammunition. Once
--a squad is down to stragglers, a captain detonates them where it hurts most
--(Posthumous Promotion), and Fodder Run spends the minion line all at once.
--Per the band's tactics, offensive war dogs bully low-Stamina heroes while
--defensive and support war dogs tie up the biggest threats.

local movementPause = 0.6
local stationaryPause = 0.35
local speechPause = 0.45
local abilityPause = 0.9
--Villain actions and Fodder Run resolve one creature after another; keep each
--beat readable without making a whole army take minutes.
local grantedActionPause = 0.5

local warDogGroup = {"War Dog"}

local warDogMonsters = {
    "War Dog Commando",
    "War Dog Conscript",
    "War Dog Sharpshooter",
    "War Dog Tetherite",
    "War Dog Amalgamite",
    "War Dog Crucibite",
    "War Dog Eviscerite",
    "War Dog Neuronite",
    "War Dog Pestilite",
    "War Dog Phosphorite",
    "War Dog Teletalite",
    "War Dog Subcommander",
    "War Dog Ground Commander",
}

--Non-minions with the Posthumous Promotion maneuver.
local warDogCaptains = {
    "War Dog Amalgamite",
    "War Dog Crucibite",
    "War Dog Eviscerite",
    "War Dog Neuronite",
    "War Dog Pestilite",
    "War Dog Phosphorite",
    "War Dog Teletalite",
    "War Dog Subcommander",
}

local causticDetonatorEffectId = "7c7cee0e-ad89-4c42-8a1d-94dec05a7b60"
local groundCommanderEndEffectGuid = "092a2ced-6872-4ca8-b864-e4cafe384f90"
--All three Final Orders triggers (condition, forced movement, death) share it.
local finalOrdersGuid = "099c88e1-cf46-44ee-8ebd-babfa8fd0e32"

--Average Loyalty Collar damage to each adjacent enemy: 1d3 for a minion, 1d6
--for anyone else.
local minionCollarDamage = 2
local captainCollarDamage = 3.5
--What a living war dog is still worth, in the same damage units: the attacks
--it would make in later rounds. A squad down to this many members is
--stragglers, and a straggler is worth less.
--A healthy minion has rounds of strikes ahead of it; a straggler will soon
--die anyway, which is when the band's tactics spend minions.
local stragglerSquadSize = 2
local minionFutureValue = 6
local stragglerFutureValue = 1.5
local captainFutureValue = 3
--A war dog that has not acted yet this round would still make its strike.
local minionStrikeValue = 2.5
--A non-minion is only ever spent at death's door.
local captainDetonationStaminaFraction = 0.2
--A detonation has to beat keeping the war dog by this much.
local detonationMinimumGain = 1
--A free strike, in the same units, for Fodder Run.
local freeStrikeValue = 2

--Spoken lines, kept together so they are easy to revise after playtesting.
local speech = {
    posthumousPromotion = {"Your service is complete.", "The Iron Saint thanks you.", "Promoted, soldier."},
    highestPromotion = {"All of you: posthumous promotion!", "Glory to the Iron Saint!"},
    fodderRun = {"Fodder, forward!", "Run, and be recycled!", "For the Iron Saint!"},
    reconstitute = {"Spare parts.", "The Body Banks provide."},
    fireForEffect = {"Fire for effect!", "Bring down the fire!"},
    combinedArms = {"Combined arms! Advance!", "All units, engage!"},
    makeAnExample = {"Make an example of that one!", "Show them the price of defiance!"},
    claimThem = {"Claim them for the Body Banks!", "Take them alive!"},
    finalOrders = {"You have your final orders.", "Die useful."},
}

--------------------------------------------------------------------------------
-- Shared helpers.
--------------------------------------------------------------------------------

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject
        and token.properties ~= nil and not token.properties:IsDead()
end

local function MonsterType(token)
    if token == nil or token.properties == nil then
        return ""
    end
    return token.properties:try_get("monster_type", "")
end

local function IsMinion(token)
    return token.properties:try_get("minion", false) == true
end

local function HasKeyword(token, keyword)
    local keywords = token.properties:try_get("keywords")
    return type(keywords) == "table" and keywords[keyword] == true
end

--Matches by keyword and by stat block, so war dogs from other content count too.
local function IsWarDog(token)
    return LiveCreature(token)
        and (HasKeyword(token, "War Dog") or string.sub(MonsterType(token), 1, 7) == "War Dog")
end

local function FindTokenByCharid(charid)
    if type(charid) ~= "string" or charid == "" then
        return nil
    end
    return dmhub.GetTokenById(charid)
end

local function FindAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name then
            return ability
        end
    end
end

local function SignatureAbility(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.categorization == "Signature Ability" then
            return ability
        end
    end
end

local function HasOngoingEffect(token, effectid)
    if not LiveCreature(token) then
        return false
    end
    for _,effect in ipairs(token.properties:ActiveOngoingEffects()) do
        if effect.ongoingEffectid == effectid then
            return true
        end
    end
    return false
end

--MaxHitpoints(), not the max_hitpoints field: on a hero that field is only
--a base value, far below the real maximum.
local function MaxStamina(token)
    return math.max(1, token.properties:MaxHitpoints())
end

--Clamped: temporary Stamina can push current Stamina above the maximum.
local function StaminaFraction(token)
    local fraction = token.properties:CurrentHitpoints() / MaxStamina(token)
    return math.max(0, math.min(1, fraction))
end

local function MissingStamina(token)
    return math.max(0, MaxStamina(token) - token.properties:CurrentHitpoints())
end

local function LocKey(loc)
    return loc.xyfloorOnly.str
end

local function Speak(ai, token, key)
    local lines = speech[key]
    if lines ~= nil and LiveCreature(token) then
        ai:Speech(token, lines)
        ai.Sleep(speechPause)
    end
end

local function MoveCinematically(ai, token, loc)
    local moving = loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc)
    if moving then
        ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
    end
    ai.Sleep(moving and movementPause or stationaryPause)
end

local function LiveEnemies(ai)
    local result = {}
    for _,enemy in ipairs(ai.enemyTokens or {}) do
        if LiveCreature(enemy) then
            result[#result+1] = enemy
        end
    end
    return result
end

--True when the creature is part of the running combat. Maps carry creatures
--that are not (props, bystander NPCs), and they must not be handed strikes.
local function InCombat(token)
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return true
    end
    local initiativeid = InitiativeQueue.GetInitiativeId(token)
    return initiativeid ~= nil and queue.entries[initiativeid] ~= nil
end

--Live creatures hostile to this one, read from the map so it also works out of turn.
local function HostileCreatures(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and not other:IsFriend(token) and InCombat(other) then
            result[#result+1] = other
        end
    end
    return result
end

local function FriendlyWarDogs(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if IsWarDog(other) and other:IsFriend(token) and InCombat(other) then
            result[#result+1] = other
        end
    end
    return result
end

local function AdjacentEnemiesAt(enemies, loc)
    local result = 0
    for _,enemy in ipairs(enemies) do
        if enemy:Distance(loc) <= 1 then
            result = result + 1
        end
    end
    return result
end

local function AdjacentEnemiesOf(token, enemies)
    local result = 0
    for _,enemy in ipairs(enemies) do
        if MonsterAI.TargetDistance(token, enemy) <= 1 then
            result = result + 1
        end
    end
    return result
end

local function CanSee(token, target)
    return token:GetLineOfSight(target, token.properties:GetPierceWalls()) > 0
end

--True when nothing but objects stands where the token would land.
local function LandingIsFree(token, loc, reserved)
    if loc == nil or not loc.valid then
        return false
    end
    for _,occupied in ipairs(token:LocsOccupyingWhenAt(loc)) do
        if reserved ~= nil and reserved[LocKey(occupied)] then
            return false
        end
        for _,other in ipairs(dmhub.GetTokensAtLoc(occupied) or {}) do
            if other.valid and other.charid ~= token.charid and not other.isObject then
                return false
            end
        end
    end
    return true
end

local function ReserveLanding(token, loc, reserved)
    for _,occupied in ipairs(token:LocsOccupyingWhenAt(loc)) do
        reserved[LocKey(occupied)] = true
    end
end

--Destroying a squad minion only deals a minion's share of the squad's
--Stamina, and records no attacker, so the squad then owes a death that the
--AI only picks for itself when an AI-controlled creature did the damage.
--Recording the detonating war dog first lets it pick the targeted minion
--instead of waiting for the Director to click the skull.
local function MarkDetonatedBy(target, detonator)
    --Not LiveCreature: a minion owing its squad's death already reads as dead.
    if target ~= nil and target.valid and target.properties ~= nil and IsMinion(target)
        and not target.properties.minionDead then
        target.properties._tmp_lastattacker = detonator.properties
    end
end

--Runs fn (a cast that may kill the band's own squad minions) while choosing
--the owed minion deaths as the AI. ExecuteAbility waits for owed deaths to be
--confirmed before it runs the AI's own chooser, so without this a cast that
--kills a friendly minion waits for the Director to click its skull.
--marks is a list of {victim, detonator}: re-applied on every pass, because
--the damage replaces the victim's properties and drops the earlier mark.
local function WithMinionDeathResolver(ai, marks, fn)
    local done = false
    dmhub.Coroutine(function()
        while not done and not mod.unloaded do
            pcall(function()
                for _,mark in ipairs(marks) do
                    MarkDetonatedBy(mark[1], mark[2])
                end
                ai:ResolvePendingMinionDeaths(0)
            end)
            coroutine.yield(0.2)
        end
    end)
    local ok, err = ai:RunYieldingFunction(fn)
    done = true
    if not ok then
        error(err)
    end
end

--Casts something that reduces these war dogs to 0 Stamina, then waits for
--their loyalty collars to go off.
local function ExecuteDetonation(ai, detonator, victims, fn)
    local marks = {}
    for _,victim in ipairs(victims) do
        marks[#marks+1] = {victim, detonator}
    end
    WithMinionDeathResolver(ai, marks, function()
        fn()
        ai:WaitForAbilityIdle(30)
    end)
end

--An area cast that may catch the band's own minions.
local function ExecuteAreaCast(ai, caster, targets, fn)
    local marks = {}
    for _,targetInfo in ipairs(targets or {}) do
        if targetInfo.token ~= nil and targetInfo.token:IsFriend(caster) then
            marks[#marks+1] = {targetInfo.token, caster}
        end
    end
    WithMinionDeathResolver(ai, marks, fn)
end

--Runs fn while the AI also answers prompts for each of these creatures.
local function WithControlOf(ai, tokens, fn)
    local controls = {}
    for _,tok in ipairs(tokens) do
        if LiveCreature(tok) then
            controls[#controls+1] = {token = tok, info = ai:BeginTokenControl(tok)}
        end
    end
    local ok, err = ai:RunYieldingFunction(fn)
    for _,control in ipairs(controls) do
        pcall(function()
            ai:EndTokenControl(control.token, control.info)
        end)
    end
    if not ok then
        error(err)
    end
end

--Casts an ability for its cost and its villain-action bookkeeping only. Used
--where the AI drives each ally's granted movement and strikes itself rather
--than answering a chain of nested prompts.
--nil targets lets a burst pick its own.
local function ActivateWithBehaviors(ai, caster, ability, behaviors, targets, options)
    local activation = DeepCopy(ability)
    activation.behaviors = behaviors or {}
    ai:ExecuteAbility(caster, activation, targets, options or {sleep = stationaryPause})
end

--The ability's own effects minus the invocations that would prompt each ally.
local function WithoutInvokes(ability)
    local result = {}
    for _,behavior in ipairs(ability.behaviors or {}) do
        if behavior.typeName ~= "ActivatedAbilityInvokeAbilityBehavior" then
            result[#result+1] = DeepCopy(behavior)
        end
    end
    return result
end

local function MaliceInCost(cost)
    local result = 0
    for _,detail in ipairs(cost.details or {}) do
        if detail.cost == CharacterResource.maliceResourceId then
            result = result + (tonumber(detail.quantity) or 0)
        end
    end
    return result
end

--An AI cast charges the ability's cost without its mode, so a Malice cost
--written per mode ("3 when mode = 2 else 0") is never paid. Charge the
--difference once the cast has gone off.
local function PayModeMalice(token, ability, mode)
    local extra = MaliceInCost(ability:GetCost(token, {mode = mode})) - MaliceInCost(ability:GetCost(token))
    if extra > 0 then
        CharacterResource.SetMalice(math.max(0, CharacterResource.GetMalice() - extra),
            string.format("%s (mode %d)", ability.name, mode))
    end
end

--------------------------------------------------------------------------------
-- Target preferences.
--------------------------------------------------------------------------------

--Offensive war dogs bully low-Stamina heroes.
local function BullyTargetScore(target, edges)
    if target.isObject or target.properties == nil then
        return 0.1 + (edges or 0)*0.1
    end
    return 1 + (edges or 0)*0.1 + (1 - StaminaFraction(target))*0.3
        + math.max(0, 1 - target.properties:CurrentHitpoints()/30)*0.15
end

--Defensive and support war dogs tie up the biggest threats.
local function ThreatTargetScore(target, edges)
    if target.isObject or target.properties == nil then
        return 0.1 + (edges or 0)*0.1
    end
    return 1 + (edges or 0)*0.1 + math.min(1, target.properties:CurrentHitpoints()/40)*0.3
end

local function SortedStrikeTargets(ai, token, ability, loc, scorefn)
    local targets = ai:FindValidTargetsOfStrike(token, ability, loc)
    table.sort(targets, function(a, b)
        return scorefn(a.token, a.edges) > scorefn(b.token, b.edges)
    end)
    table.resize_array(targets, ability:GetNumTargets(token))
    return targets
end

local function StrikeScore(baseScore, scorefn)
    return function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, scorefn)
        if loc ~= nil and targetScore ~= nil and targetScore > 0 then
            return {
                score = baseScore + math.min(0.2, math.max(0, targetScore - 1)*0.1),
                loc = loc,
            }
        end
        return nil, "no enemy can be struck this turn"
    end
end

local function StrikeExecute(scorefn)
    return function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, scorefn)
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end
end

--Forced movement uses the shared handlers. When the target cannot be moved
--usefully, skip it rather than stall the turn on a Director prompt.
local function RegisterForcedMovementFallback(monsterType, promptName)
    MonsterAI:RegisterPrompt{
        prompts = {monsterType .. ":" .. promptName},
        handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
            local generic = MonsterAI.prompts[promptName]
            local result = nil
            if generic ~= nil then
                result = generic.handler(ai, invokerToken, casterToken, abilityClone, symbols, options)
            end
            return result or {targets = {}}
        end,
    }
end

--The fragile ranged war dogs would otherwise spend a spare maneuver walking
--into melee for the generic Knockback, Grab or Aid Attack. Off by default for
--them; the Monster AI panel can still turn them back on.
local rangedWarDogs = {"War Dog Pestilite", "War Dog Phosphorite", "War Dog Crucibite", "War Dog Teletalite"}
for _,monsterType in ipairs(rangedWarDogs) do
    for _,moveid in ipairs({"Knockback", "Grab", "Aid Attack"}) do
        MonsterAI:SetMoveEnabledForMonster(monsterType, moveid, false)
    end
end

--------------------------------------------------------------------------------
-- Free strikes the AI grants and drives itself.
--------------------------------------------------------------------------------

--The creature's free strikes, ready to cast outside its action economy. Each
--entry has the clone to cast and one to plan with: the planner treats any
--"Melee Free Strike" as able to charge, which a granted strike cannot.
local function FreeStrikeOptions(actor, kinds)
    local result = {}
    for _,ability in ipairs(actor.properties:GetActivatedAbilities()) do
        if (ability.name == "Melee Free Strike" and (kinds == nil or kinds.melee))
            or (ability.name == "Ranged Free Strike" and (kinds == nil or kinds.ranged)) then
            local activation = DeepCopy(ability)
            activation.actionResourceId = "none"
            activation.disableSquadCoordination = true
            if activation.keywords ~= nil then
                activation.keywords.Charge = nil
            end
            local planning = DeepCopy(activation)
            planning.name = "Granted Free Strike"
            result[#result+1] = {activation = activation, planning = planning}
        end
    end
    return result
end

local function FreeStrikeReach(actor)
    local reach = 0
    for _,ability in ipairs(actor.properties:GetActivatedAbilities()) do
        if ability.name == "Melee Free Strike" or ability.name == "Ranged Free Strike" then
            reach = math.max(reach, ability:GetRange(actor.properties))
        end
    end
    return reach
end

--The best free strike this creature could make from loc, optionally only
--against one target.
local function BestFreeStrikeFrom(ai, actor, loc, options, scorefn, onlyTarget)
    scorefn = scorefn or BullyTargetScore
    --Granted strikes come one after another while war dogs blow up; the
    --planner's tactics read the AI's cached ally list and fail on one that has
    --since been removed, so re-read who is still fighting first.
    local queue = dmhub.initiativeQueue
    if queue ~= nil and not queue.hidden then
        ai:RefreshCombatants(queue, actor)
    end
    local best = nil
    for _,option in ipairs(options) do
        local range = option.planning:GetRange(actor.properties)
        for _,info in ipairs(ai:FindValidTargetsOfStrike(actor, option.planning, loc, range)) do
            if onlyTarget == nil or info.token.charid == onlyTarget.charid then
                local utility = scorefn(info.token, info.edges)
                if best == nil or utility > best.utility then
                    best = {activation = option.activation, target = info.token, utility = utility}
                end
            end
        end
    end
    return best
end

local function ExecuteFreeStrike(ai, actor, strike)
    if strike == nil or not LiveCreature(actor) or not LiveCreature(strike.target) then
        return false
    end
    ai:ExecuteAbility(actor, strike.activation, {{token = strike.target}}, {sleep = grantedActionPause})
    return true
end

--The cheapest square within movement from which the actor can free strike the
--target, or nil.
local function FindFreeStrikeApproach(ai, actor, target, movement)
    local options = FreeStrikeOptions(actor)
    local here = BestFreeStrikeFrom(ai, actor, actor.loc, options, nil, target)
    if here ~= nil then
        return {loc = actor.loc, strike = here, cost = 0}
    end
    if movement <= 0 then
        return nil
    end
    local reach = FreeStrikeReach(actor)
    local candidates = {}
    for _,info in pairs(actor:CalculatePathfindingArea(movement*10, {})) do
        if info.loc ~= nil and LandingIsFree(actor, info.loc)
            and info.loc:DistanceInTiles(target.loc) <= reach + 1 then
            candidates[#candidates+1] = {loc = info.loc, cost = info.cost or 0}
        end
    end
    table.sort(candidates, function(a, b) return a.cost < b.cost end)
    for i=1,math.min(12, #candidates) do
        local strike = BestFreeStrikeFrom(ai, actor, candidates[i].loc, options, nil, target)
        if strike ~= nil then
            return {loc = candidates[i].loc, strike = strike, cost = candidates[i].cost}
        end
    end
end

--------------------------------------------------------------------------------
-- Loyalty collars.
--------------------------------------------------------------------------------

local function SquadSize(minion)
    local squad = minion.properties:MinionSquad()
    if squad == nil then
        return 1
    end
    local count = 0
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and IsMinion(other) and other:IsFriend(minion)
            and other.properties:MinionSquad() == squad then
            count = count + 1
        end
    end
    return count
end

--True when this creature still has a turn coming this round: it is acting
--now and has not used its signature yet, or its initiative entry has not gone.
local function StillToActThisRound(token)
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return false
    end
    local initiativeid = InitiativeQueue.GetInitiativeId(token)
    if initiativeid == nil then
        return false
    end
    if initiativeid == queue:CurrentInitiativeId() then
        local signature = SignatureAbility(token)
        return signature ~= nil and signature:CanAfford(token)
    end
    local entry = queue.entries[initiativeid]
    return entry ~= nil and (tonumber(entry.round) or 0) <= queue.round
end

--What the band is still owed by this war dog if it lives, in damage units.
local function KeepValue(warDog, ignoreThisRound)
    local value
    if IsMinion(warDog) then
        value = cond(SquadSize(warDog) <= stragglerSquadSize, stragglerFutureValue, minionFutureValue)
    else
        value = captainFutureValue
    end
    if not ignoreThisRound and StillToActThisRound(warDog) then
        value = value + minionStrikeValue
    end
    return value
end

--What detonating a war dog's collar where it stands gains over keeping it.
--Returns nil for a non-minion that is not at death's door.
local function DetonationGain(warDog, enemies)
    local adjacent = AdjacentEnemiesOf(warDog, enemies)
    if IsMinion(warDog) then
        return adjacent*minionCollarDamage - KeepValue(warDog), adjacent
    end
    if StaminaFraction(warDog) > captainDetonationStaminaFraction then
        return nil, adjacent
    end
    return adjacent*captainCollarDamage - KeepValue(warDog), adjacent
end

local function FindPromotionPlan(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local enemies = LiveEnemies(ai)
    local best = nil
    for _,ally in ipairs(FriendlyWarDogs(token)) do
        if ally.charid ~= token.charid and MonsterAI.TargetDistance(token, ally) <= range
            and ability:TargetPassesFilter(token, ally, {}) and CanSee(token, ally) then
            local gain, adjacent = DetonationGain(ally, enemies)
            if gain ~= nil and adjacent > 0 and gain >= detonationMinimumGain
                and (best == nil or gain > best.gain) then
                best = {target = ally, targets = {{token = ally}}, gain = gain, adjacent = adjacent}
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "War Dog: Posthumous Promotion",
    category = "Maneuvers",
    monsters = warDogCaptains,
    abilities = {"Posthumous Promotion"},
    description = "Detonate a war dog's loyalty collar beside enemies once that is worth more than the war dog: stragglers, minions who have already struck this round, and allies at death's door.",
    score = function(self, ai, token, ability)
        local plan = FindPromotionPlan(ai, token, ability)
        if plan == nil then
            return nil, "no collared ally is worth more exploded than alive"
        end
        plan.score = 0.6 + math.min(0.35, plan.gain*0.08)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        if not LiveCreature(scoringInfo.target) then
            return
        end
        Speak(ai, token, "posthumousPromotion")
        local target = scoringInfo.target
        ExecuteDetonation(ai, token, {target}, function()
            ai:ExecuteAbility(token, ability, {{token = target}}, {sleep = abilityPause})
        end)
    end,
}

--------------------------------------------------------------------------------
-- Area placement.
--------------------------------------------------------------------------------

local function CopySymbols(symbols)
    local result = {}
    for key,value in pairs(symbols or {}) do
        result[key] = value
    end
    return result
end

local function TokensInArea(casterToken, ability, area, symbols)
    local result = {}
    symbols = CopySymbols(symbols)
    symbols.targetArea = area
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if target.valid and ability:TargetPassesFilter(casterToken, target, symbols) then
            result[#result+1] = {token = target}
        end
    end
    return result
end

--Allies caught in war dog areas: a minion is cheap, anyone else is not.
local function AreaValue(caster, targets, weights)
    local value = 0
    local enemies = 0
    local allies = 0
    for _,targetInfo in ipairs(targets) do
        local target = targetInfo.token
        if LiveCreature(target) then
            if target:IsFriend(caster) then
                allies = allies + 1
                value = value + cond(IsMinion(target), weights.minionAlly, weights.ally)
            else
                enemies = enemies + 1
                value = value + weights.enemy
            end
        end
    end
    return value, enemies, allies
end

local function DestroyArea(area)
    if area ~= nil and type(area.Destroy) == "function" then
        area:Destroy()
    end
end

local function BuildCubeArea(token, ability, center, originLoc, symbols)
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(center),
        token = token,
        range = ability:GetRange(token.properties, symbols),
        radius = ability:GetRadius(token.properties, symbols),
        locOverride = originLoc,
        checklos = false,
        altitude = center.altitude * dmhub.unitsPerSquare,
    }
end

--The best cube for an area ability. origins are squares the caster could
--cast from, {loc, cost}; centers are tried on and around each enemy.
local function FindBestCubePlan(ai, token, ability, origins, weights, symbols)
    local range = ability:GetRange(token.properties, symbols)
    local radius = ability:GetRadius(token.properties, symbols)
    local spread = cond(radius >= 3, 1, 0)
    local pierceWalls = token.properties:GetPierceWalls()
    table.sort(origins, function(a, b) return (a.cost or 0) < (b.cost or 0) end)

    local seen = {}
    local best = nil
    for _,enemy in ipairs(LiveEnemies(ai)) do
        for dx=-spread,spread do
            for dy=-spread,spread do
                local center = enemy.loc:dir(dx, dy)
                local key = center.valid and LocKey(center) or nil
                if key ~= nil and not seen[key] then
                    seen[key] = true
                    --The cheapest origin in range with line of effect to the center.
                    local origin = nil
                    local checks = 0
                    for _,candidate in ipairs(origins) do
                        if checks >= 12 then
                            break
                        end
                        if candidate.loc:DistanceInTiles(center) <= range then
                            checks = checks + 1
                            local visible = false
                            ai:ExecuteWithTheoreticalMovementLoc(token, candidate.loc, function()
                                visible = token:GetLineOfSight(center, pierceWalls) > 0
                            end)
                            if visible then
                                origin = candidate
                                break
                            end
                        end
                    end

                    if origin ~= nil then
                        local area = BuildCubeArea(token, ability, center, origin.loc, symbols)
                        local targets = TokensInArea(token, ability, area, symbols)
                        DestroyArea(area)
                        local value, enemies, allies = AreaValue(token, targets, weights)
                        local utility = value - (origin.cost or 0)*0.001
                        if enemies > 0 and (best == nil or utility > best.utility) then
                            best = {
                                loc = origin.loc,
                                center = center,
                                value = value,
                                enemies = enemies,
                                allies = allies,
                                utility = utility,
                            }
                        end
                    end
                end
            end
        end
    end
    return best
end

local function PathOrigins(ai)
    local result = {}
    for _,info in pairs(ai.paths or {}) do
        result[#result+1] = {loc = info.loc, cost = info.cost or 0}
    end
    return result
end

--Builds the cube at its center from where the caster now stands and casts it.
local function ExecuteCubePlan(ai, token, ability, center, symbols)
    local area = BuildCubeArea(token, ability, center, nil, symbols)
    local targets = TokensInArea(token, ability, area, symbols)
    local castSymbols = CopySymbols(symbols)
    castSymbols.targetArea = area
    ExecuteAreaCast(ai, token, targets, function()
        ai:ExecuteAbility(token, ability, targets, {
            sleep = abilityPause,
            symbols = castSymbols,
            targetArea = area,
        })
    end)
    DestroyArea(area)
end

--------------------------------------------------------------------------------
-- Strikes.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "War Dog Amalgamite: Several Arms",
    category = "Main Actions",
    monsters = {"War Dog Amalgamite"},
    abilities = {"Several Arms"},
    description = "Grab two creatures within 2, preferring low-Stamina heroes.",
    score = StrikeScore(1.0, BullyTargetScore),
    execute = StrikeExecute(BullyTargetScore),
}

--Several Arms' "3 Malice" rider arrives as a confirm-or-skip prompt after the
--strike: 3 damage to each creature the amalgamite has grabbed, healing it as
--much. Taken when the band can pay for it and it is worth it.
local severalArmsMaliceCost = 3

MonsterAI:RegisterPrompt{
    prompts = {"War Dog Amalgamite:Invoked Ability"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if CharacterResource.GetMalice() < severalArmsMaliceCost then
            return {targets = {}}
        end
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        local targets = {}
        for _,other in ipairs(HostileCreatures(casterToken)) do
            if MonsterAI.TargetDistance(casterToken, other) <= range
                and abilityClone:TargetPassesFilter(casterToken, other, symbols or {}) then
                targets[#targets+1] = {token = other}
            end
        end
        --One grabbed creature is only worth it when the healing is wanted too.
        if #targets == 0 or (#targets == 1 and MissingStamina(casterToken) < 3) then
            return {targets = {}}
        end
        --The content's rider costs nothing, though the book prices it at 3
        --Malice; pay it here unless the content has started charging.
        if MaliceInCost(abilityClone:GetCost(casterToken)) == 0 then
            CharacterResource.SetMalice(CharacterResource.GetMalice() - severalArmsMaliceCost, "Several Arms")
        end
        return {targets = targets}
    end,
}

MonsterAI:RegisterMove{
    id = "War Dog Eviscerite: Chainsaw Whip",
    category = "Main Actions",
    monsters = {"War Dog Eviscerite"},
    abilities = {"Chainsaw Whip"},
    description = "Whip a low-Stamina hero from up to 3 squares away and drag them in.",
    score = StrikeScore(1.0, BullyTargetScore),
    execute = StrikeExecute(BullyTargetScore),
}

RegisterForcedMovementFallback("War Dog Eviscerite", "Pull!")

--Corrupted Ash Daggers gains an edge when any ally is next to the target.
local function TeletaliteTargetScore(target, edges)
    local score = BullyTargetScore(target, edges)
    if target.isObject or target.properties == nil then
        return score
    end
    for _,ally in ipairs(dmhub.allTokens) do
        if LiveCreature(ally) and not target:IsFriend(ally) and IsWarDog(ally)
            and MonsterAI.TargetDistance(ally, target) <= 1 then
            return score + 0.2
        end
    end
    return score
end

MonsterAI:RegisterMove{
    id = "War Dog Teletalite: Corrupted Ash Daggers",
    category = "Main Actions",
    monsters = {"War Dog Teletalite"},
    abilities = {"Corrupted Ash Daggers"},
    description = "Knife a low-Stamina hero, preferring one an ally stands next to for the edge.",
    score = StrikeScore(1.0, TeletaliteTargetScore),
    execute = StrikeExecute(TeletaliteTargetScore),
}

RegisterForcedMovementFallback("War Dog Teletalite", "Slide!")

--A second detonator on the same creature only rerolls the same explosion.
local function CausticDetonatorTargetScore(target, edges)
    local score = BullyTargetScore(target, edges)
    if not target.isObject and HasOngoingEffect(target, causticDetonatorEffectId) then
        score = score - 0.7
    end
    return score
end

MonsterAI:RegisterMove{
    id = "War Dog Phosphorite: Caustic Detonator",
    category = "Main Actions",
    monsters = {"War Dog Phosphorite"},
    abilities = {"Caustic Detonator"},
    description = "Plant a detonator on a low-Stamina hero who does not already carry one.",
    score = StrikeScore(1.0, CausticDetonatorTargetScore),
    execute = StrikeExecute(CausticDetonatorTargetScore),
}

--------------------------------------------------------------------------------
-- Subcommander: Command Saber, and the ally free strike it grants.
--------------------------------------------------------------------------------

--A friendly creature near the commander who could free strike the target
--without moving, if any.
local function FindAllyFreeStriker(ai, commander, target, range, filter)
    local best = nil
    for _,ally in ipairs(dmhub.allTokens) do
        if LiveCreature(ally) and ally.charid ~= commander.charid and ally:IsFriend(commander)
            and not ally.playerControlled and InCombat(ally)
            and MonsterAI.TargetDistance(commander, ally) <= range
            and (filter == nil or filter(ally)) then
            local strike = BestFreeStrikeFrom(ai, ally, ally.loc, FreeStrikeOptions(ally), nil, target)
            if strike ~= nil then
                --Non-minions hit harder; among equals keep the nearer one.
                local utility = cond(IsMinion(ally), 0, 1) - MonsterAI.TargetDistance(commander, ally)*0.01
                if best == nil or utility > best.utility then
                    best = {token = ally, strike = strike, utility = utility}
                end
            end
        end
    end
    return best
end

local function CommandSaberTargetScore(target, edges)
    local score = ThreatTargetScore(target, edges)
    if target.isObject or target.properties == nil then
        return score
    end
    --An ally beside the target can take the granted free strike.
    for _,ally in ipairs(dmhub.allTokens) do
        if LiveCreature(ally) and not ally:IsFriend(target) and IsWarDog(ally)
            and MonsterAI.TargetDistance(ally, target) <= math.max(1, FreeStrikeReach(ally)) then
            return score + 0.25
        end
    end
    return score
end

--Allies within this range may be handed Command Saber's free strike.
local commandSaberAllyRange = 5

MonsterAI:RegisterMove{
    id = "War Dog Subcommander: Command Saber",
    category = "Main Actions",
    monsters = {"War Dog Subcommander"},
    abilities = {"Command Saber"},
    description = "Hold down the biggest threat in reach, preferring one an ally can also free strike.",
    score = StrikeScore(1.0, CommandSaberTargetScore),
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, CommandSaberTargetScore)
        if #targets == 0 then
            return
        end
        local allies = {}
        for _,ally in ipairs(ai.allyTokens or {}) do
            if LiveCreature(ally) and MonsterAI.TargetDistance(token, ally) <= commandSaberAllyRange then
                allies[#allies+1] = ally
            end
        end
        ai._tmp_warDogFreeStrikeTarget = targets[1].token.charid
        WithControlOf(ai, allies, function()
            ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
        end)
        ai._tmp_warDogFreeStrikeTarget = nil
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"War Dog Subcommander:Ally Makes Free Strike Against Specific Target"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local target = FindTokenByCharid(ai:try_get("_tmp_warDogFreeStrikeTarget"))
        if not LiveCreature(target) then
            return {targets = {}}
        end
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        local best = FindAllyFreeStriker(ai, casterToken, target, range, function(ally)
            return abilityClone:TargetPassesFilter(casterToken, ally, symbols or {})
        end)
        if best == nil then
            return {targets = {}}
        end
        return {targets = {{token = best.token}}}
    end,
}

--The granted free strike against the commanded target, made by whichever
--war dog was chosen. Restricted to that target.
local specificFreeStrikePrompts = {}
for _,monsterType in ipairs(warDogMonsters) do
    specificFreeStrikePrompts[#specificFreeStrikePrompts+1] = monsterType .. ":Free Strike Against Specific Target"
end

MonsterAI:RegisterPrompt{
    prompts = specificFreeStrikePrompts,
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local target = FindTokenByCharid(ai:try_get("_tmp_warDogFreeStrikeTarget"))
        if not LiveCreature(target) or not LiveCreature(casterToken) then
            return {targets = {}}
        end
        local synthesized = abilityClone:SynthesizeAbilities(casterToken.properties) or {}
        for _,ability in ipairs(synthesized) do
            if MonsterAI.TargetDistance(casterToken, target) <= ability:GetRange(casterToken.properties)
                and ability:TargetPassesFilter(casterToken, target, symbols or {})
                and CanSee(casterToken, target) then
                return {
                    targets = {{token = target}},
                    abilityOverride = ability,
                }
            end
        end
        return {targets = {}}
    end,
}

--------------------------------------------------------------------------------
-- Crucibite: Flamebelcher.
--------------------------------------------------------------------------------

--Mode 1 burns allies like anyone else. Mode 2 (3 Malice) is twice as long and
--deals extra damage to everyone when an ally is caught, so a minion in the
--line is welcome there.
local flamebelcherWeights = {
    [1] = {enemy = 1, minionAlly = -0.3, ally = -1},
    [2] = {enemy = 1, minionAlly = 0.4, ally = -0.6},
}

local function FindFlamebelcherPlan(ai, token, ability, mode)
    local symbols = {mode = mode}
    local length = ability:GetRange(token.properties, symbols)
    local enemies = LiveEnemies(ai)
    local candidates = {}
    for _,info in pairs(ai.paths or {}) do
        for _,enemy in ipairs(enemies) do
            if info.loc:DistanceInTiles(enemy.loc) <= length + 1 then
                candidates[#candidates+1] = {targetLoc = enemy.loc, locOverride = info.loc, cost = info.cost or 0}
            end
        end
    end
    if #candidates == 0 then
        return nil
    end

    local weights = flamebelcherWeights[mode]
    local plan = ai:FindBestLinePlan(token, ability, {
        candidates = candidates,
        symbols = symbols,
        logPlan = false,
        scorefn = function(target, candidate)
            if target.isObject or not LiveCreature(target) then
                return 0
            end
            local weight
            if target:IsFriend(token) then
                weight = cond(IsMinion(target), weights.minionAlly, weights.ally)
            else
                weight = weights.enemy
            end
            return weight - (candidate.cost or 0)*0.0001
        end,
    })
    if plan == nil then
        return nil
    end
    local value, enemyCount, allyCount = AreaValue(token, plan.targets, weights)
    if enemyCount == 0 then
        return nil
    end
    return {
        mode = mode,
        loc = plan.locOverride,
        targetLoc = plan.targetLoc,
        value = value,
        enemies = enemyCount,
        allies = allyCount,
    }
end

MonsterAI:RegisterMove{
    id = "War Dog Crucibite: Flamebelcher",
    category = "Main Actions",
    monsters = {"War Dog Crucibite"},
    abilities = {"Flamebelcher"},
    description = "Hose the most enemies with sticky fire, accepting minions in the line; spend 3 Malice on the 10-square line when it catches clearly more.",
    score = function(self, ai, token, ability)
        local plan = FindFlamebelcherPlan(ai, token, ability, 1)
        if ability:CanAfford(token, {mode = 2}) then
            local longPlan = FindFlamebelcherPlan(ai, token, ability, 2)
            if longPlan ~= nil and longPlan.enemies >= 2
                and (plan == nil or longPlan.value >= plan.value + 1) then
                plan = longPlan
            end
        end
        if plan == nil or plan.value <= 0.5 then
            return nil, "no line catches enough enemies for its friendly fire"
        end
        plan.score = 1.0 + math.min(0.4, (plan.value - 1)*0.15)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local symbols = {mode = scoringInfo.mode}
        local activation = ability:SwitchModes(scoringInfo.mode)
        local area = dmhub.CalculateShape{
            shape = "line",
            targetPoint = token:PosAtLoc(scoringInfo.targetLoc),
            token = token,
            range = activation:GetRange(token.properties, symbols),
            radius = activation:GetRadius(token.properties, symbols),
            checklos = true,
            altitude = token.loc.altitude * dmhub.unitsPerSquare,
        }
        local targets = TokensInArea(token, activation, area, symbols)
        symbols.targetArea = area
        local cast = false
        ExecuteAreaCast(ai, token, targets, function()
            cast = ai:ExecuteAbility(token, activation, targets, {
                sleep = abilityPause,
                symbols = symbols,
                targetArea = area,
            }) ~= false
        end)
        if cast then
            PayModeMalice(token, ability, scoringInfo.mode)
        end
        DestroyArea(area)
    end,
}

--------------------------------------------------------------------------------
-- Pestilite: Plaguecaster.
--------------------------------------------------------------------------------

--The cloud lingers, so allies inside keep choking; minions are expendable.
local plaguecasterWeights = {enemy = 1, minionAlly = -0.4, ally = -1.5}

MonsterAI:RegisterMove{
    id = "War Dog Pestilite: Plaguecaster",
    category = "Main Actions",
    monsters = {"War Dog Pestilite"},
    abilities = {"Plaguecaster"},
    description = "Drop the pestilence cloud on the most enemies, accepting minions inside but not other allies.",
    score = function(self, ai, token, ability)
        local plan = FindBestCubePlan(ai, token, ability, PathOrigins(ai), plaguecasterWeights, {})
        if plan == nil or plan.value <= 0.5 then
            return nil, "no cube catches enough enemies for its friendly fire"
        end
        plan.score = 1.0 + math.min(0.4, (plan.value - 1)*0.15)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ExecuteCubePlan(ai, token, ability, scoringInfo.center, {})
    end,
}

--------------------------------------------------------------------------------
-- Neuronite: Synlirii Grafts and The Voice.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "War Dog Neuronite: Synlirii Grafts",
    category = "Main Actions",
    monsters = {"War Dog Neuronite"},
    abilities = {"Synlirii Grafts"},
    description = "Float into the middle of as many enemies as possible, favouring the sturdiest, and throw them about.",
    score = function(self, ai, token, ability)
        local loc, value = ai:FindBestMoveToUseBurst(token, ability, function(target)
            if target.isObject or not LiveCreature(target) then
                return 0
            end
            return 1 + math.min(1, target.properties:CurrentHitpoints()/40)*0.1
        end)
        if loc == nil or value == nil or value < 1 then
            return nil, "no enemy can be reached with the 1 burst"
        end
        return {loc = loc, score = 1.0 + math.min(0.4, (value - 1)*0.15)}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

RegisterForcedMovementFallback("War Dog Neuronite", "Slide!")

local voiceAllyRange = 10
local voiceTaunterMinimumStamina = 15

local function VoiceTargets(token, ability)
    local range = ability:GetRange(token.properties)
    local result = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        if MonsterAI.TargetDistance(token, enemy) <= range
            and ability:TargetPassesFilter(token, enemy, {}) then
            result[#result+1] = enemy
        end
    end
    return result
end

--Damage immunity protects a wounded non-minion ally the targets are on.
local function FindVoiceProtectee(token, targets)
    local best = nil
    for _,ally in ipairs(FriendlyWarDogs(token)) do
        if ally.charid ~= token.charid and not IsMinion(ally)
            and MonsterAI.TargetDistance(token, ally) <= voiceAllyRange
            and StaminaFraction(ally) <= 0.5 then
            local threats = AdjacentEnemiesOf(ally, targets)
            if threats > 0 then
                local utility = threats + (1 - StaminaFraction(ally))
                if best == nil or utility > best.utility then
                    best = {token = ally, threats = threats, utility = utility}
                end
            end
        end
    end
    return best
end

--Taunting the targets onto the sturdiest non-minion ally near them.
local function FindVoiceTaunter(token, targets)
    local best = nil
    for _,ally in ipairs(FriendlyWarDogs(token)) do
        --A taunter has to be able to take the hits it draws: never a fragile
        --artillery war dog.
        if ally.charid ~= token.charid and not IsMinion(ally)
            and MonsterAI.TargetDistance(token, ally) <= voiceAllyRange
            and StaminaFraction(ally) >= 0.5
            and ally.properties:CurrentHitpoints() >= voiceTaunterMinimumStamina then
            local nearby = 0
            for _,target in ipairs(targets) do
                if MonsterAI.TargetDistance(ally, target) <= 3 then
                    nearby = nearby + 1
                end
            end
            local utility = ally.properties:CurrentHitpoints()*0.05 + nearby*0.2
            if best == nil or utility > best.utility then
                best = {token = ally, utility = utility}
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "War Dog Neuronite: The Voice (Damage Immunity)",
    category = "Maneuvers",
    monsters = {"War Dog Neuronite"},
    abilities = {"The Voice - Damage Immunity"},
    description = "Spend 1 Malice to shield a wounded non-minion ally with damage immunity 3 against two or more enemies in the 5 burst.",
    score = function(self, ai, token, ability)
        local targets = VoiceTargets(token, ability)
        if #targets < 2 then
            return nil, "fewer than two enemies in the 5 burst"
        end
        local protectee = FindVoiceProtectee(token, targets)
        if protectee == nil then
            return nil, "no wounded non-minion ally is under attack by the targets"
        end
        return {
            score = math.min(0.9, 0.7 + protectee.threats*0.05 + #targets*0.02),
            ally = protectee.token,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai._tmp_warDogVoiceAlly = scoringInfo.ally.charid
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        ai._tmp_warDogVoiceAlly = nil
    end,
}

MonsterAI:RegisterMove{
    id = "War Dog Neuronite: The Voice (Taunt)",
    category = "Maneuvers",
    monsters = {"War Dog Neuronite"},
    abilities = {"The Voice - Taunt"},
    description = "Spend 1 Malice to taunt two or more enemies in the 5 burst onto the sturdiest non-minion ally nearby.",
    score = function(self, ai, token, ability)
        local targets = VoiceTargets(token, ability)
        if #targets < 2 then
            return nil, "fewer than two enemies in the 5 burst"
        end
        local taunter = FindVoiceTaunter(token, targets)
        if taunter == nil then
            return nil, "no healthy non-minion ally within 10 squares"
        end
        return {
            score = math.min(0.85, 0.65 + #targets*0.04),
            ally = taunter.token,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai._tmp_warDogVoiceAlly = scoringInfo.ally.charid
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        ai._tmp_warDogVoiceAlly = nil
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"War Dog Neuronite:AllyTaunt", "War Dog Neuronite:The Voice - Ally Selection"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        local planned = FindTokenByCharid(ai:try_get("_tmp_warDogVoiceAlly"))
        if LiveCreature(planned) and MonsterAI.TargetDistance(casterToken, planned) <= range
            and abilityClone:TargetPassesFilter(casterToken, planned, symbols or {}) then
            return {targets = {{token = planned}}}
        end
        --No plan survived: protect whoever needs it, else taunt onto the toughest.
        local targets = HostileCreatures(casterToken)
        local fallback = FindVoiceProtectee(casterToken, targets) or FindVoiceTaunter(casterToken, targets)
        if fallback ~= nil and abilityClone:TargetPassesFilter(casterToken, fallback.token, symbols or {}) then
            return {targets = {{token = fallback.token}}}
        end
        return {targets = {}}
    end,
}

--------------------------------------------------------------------------------
-- Teletalite: Corrupted Ash Teleport.
--------------------------------------------------------------------------------

--A square to knife from: clear of enemies, with a target in Daggers reach.
local function TeleportLandingScore(ai, token, loc, enemies, reach)
    local nearest = 999
    local adjacent = 0
    for _,enemy in ipairs(enemies) do
        local distance = enemy:Distance(loc)
        nearest = math.min(nearest, distance)
        if distance <= 1 then
            adjacent = adjacent + 1
        end
    end
    local score = -adjacent*3
    if nearest <= reach then
        score = score + 2
    else
        score = score - (nearest - reach)
    end
    --Ambushers like a little distance.
    if nearest >= 3 and nearest <= 6 then
        score = score + 0.5
    end
    return score
end

local function FindTeleportPlan(ai, token, ability, daggers)
    local range = ability:GetRange(token.properties)
    local enemies = LiveEnemies(ai)
    if #enemies == 0 then
        return nil
    end
    local reach = daggers ~= nil and daggers:GetRange(token.properties) or 10
    local current = TeleportLandingScore(ai, token, token.loc, enemies, reach)
    local shape = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = token,
        radius = range,
        checklos = true,
    }
    local best = nil
    for _,loc in ipairs(shape.locations or {}) do
        if LocKey(loc) ~= LocKey(token.loc) and LandingIsFree(token, loc) then
            local score = TeleportLandingScore(ai, token, loc, enemies, reach)
                - token.loc:DistanceInTiles(loc)*0.01
            if best == nil or score > best.value then
                best = {loc = loc, value = score}
            end
        end
    end
    if best == nil or best.value <= current + 1 then
        return nil
    end
    return best
end

MonsterAI:RegisterMove{
    id = "War Dog Teletalite: Corrupted Ash Teleport",
    category = "Maneuvers",
    monsters = {"War Dog Teletalite"},
    abilities = {"Corrupted Ash Teleport"},
    description = "Spend 1 Malice to teleport out of an enemy's reach: before knifing for the edge, or after knifing to get clear.",
    score = function(self, ai, token, ability)
        local enemies = LiveEnemies(ai)
        if AdjacentEnemiesOf(token, enemies) == 0 then
            return nil, "no enemy is adjacent; walking costs no Malice"
        end
        local daggers = FindAbility(token, "Corrupted Ash Daggers")
        local plan = FindTeleportPlan(ai, token, ability, daggers)
        if plan == nil then
            return nil, "no clearly better square within 5"
        end
        --Before the strike it must outrank Daggers so the edge applies to it.
        if daggers ~= nil and daggers:CanAfford(token) then
            plan.score = 1.3
        else
            plan.score = 0.6
        end
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:ExecuteAbility(token, ability, {{loc = scoringInfo.loc}}, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Ground Commander.
--------------------------------------------------------------------------------

local grabbedConditionId = "70504ebe-3899-41d3-9f60-74b52ce35e39"

--How many creatures this creature has grabbed.
local function GrabbedBy(token)
    local count = 0
    token.properties:VisitConditionCasterSource(function(condid, grabbedToken)
        if condid == grabbedConditionId and LiveCreature(grabbedToken) then
            count = count + 1
        end
    end)
    return count
end

local function ConditioningSpearMode(ai, token, ability, loc, targets)
    if CharacterResource.GetMalice() < 1 or not ability:CanAfford(token, {mode = 2}) then
        return 1
    end
    if GrabbedBy(token) >= 2 then
        return 1
    end
    --Pull 1-3 brings a target within 2 next to the commander.
    for _,targetInfo in ipairs(targets) do
        if not targetInfo.token.isObject and targetInfo.token:Distance(loc) <= 2 then
            return 2
        end
    end
    return 1
end

MonsterAI:RegisterMove{
    id = "War Dog Ground Commander: Conditioning Spear",
    category = "Main Actions",
    monsters = {"War Dog Ground Commander"},
    abilities = {"Conditioning Spear"},
    description = "Spear two low-Stamina heroes, hand an ally a free strike, and spend 1 Malice to hold a target dragged next to the commander.",
    score = StrikeScore(1.1, BullyTargetScore),
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, BullyTargetScore)
        if #targets == 0 then
            return
        end
        local mode = ConditioningSpearMode(ai, token, ability, scoringInfo.loc, targets)
        local allies = {}
        for _,ally in ipairs(ai.allyTokens or {}) do
            if LiveCreature(ally) and MonsterAI.TargetDistance(token, ally) <= 10 then
                allies[#allies+1] = ally
            end
        end
        WithControlOf(ai, allies, function()
            ai:ExecuteAbility(token, ability:SwitchModes(mode), targets, {
                sleep = abilityPause,
                symbols = {mode = mode},
            })
        end)
    end,
}

RegisterForcedMovementFallback("War Dog Ground Commander", "Pull!")

MonsterAI:RegisterPrompt{
    prompts = {"War Dog Ground Commander:Conditioning Spear Effect"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        local best = nil
        for _,ally in ipairs(dmhub.allTokens) do
            if LiveCreature(ally) and ally.charid ~= casterToken.charid and ally:IsFriend(casterToken)
                and not ally.playerControlled and InCombat(ally)
                and MonsterAI.TargetDistance(casterToken, ally) <= range
                and abilityClone:TargetPassesFilter(casterToken, ally, symbols or {})
                and CanSee(casterToken, ally) then
                local strike = BestFreeStrikeFrom(ai, ally, ally.loc, FreeStrikeOptions(ally))
                if strike ~= nil then
                    local utility = strike.utility + cond(IsMinion(ally), 0, 0.5)
                    if best == nil or utility > best.utility then
                        best = {token = ally, utility = utility}
                    end
                end
            end
        end
        if best == nil then
            return {targets = {}}
        end
        return {targets = {{token = best.token}}}
    end,
}

--Highest Posthumous Promotion detonates every collared war dog in a 10 burst,
--so it is only worth it once everyone in range is a straggler or already spent.
local function FindHighestPromotionPlan(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local enemies = LiveEnemies(ai)
    local total = 0
    local exploding = 0
    local targets = 0
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and other.charid ~= token.charid
            and MonsterAI.TargetDistance(token, other) <= range
            and ability:TargetPassesFilter(token, other, {}) then
            if not other:IsFriend(token) then
                return nil, "an enemy wears a loyalty collar in range"
            end
            targets = targets + 1
            local gain, adjacent = DetonationGain(other, enemies)
            if gain == nil then
                return nil, "a healthy non-minion war dog is in range"
            end
            total = total + gain
            if adjacent > 0 then
                exploding = exploding + 1
            end
        end
    end
    if exploding < 2 or total < 4 then
        return nil, string.format("detonating %d war dogs gains only %.1f", targets, total)
    end
    --Not "targets": the decision log reads that field as a target list.
    return {gain = total, exploding = exploding, collared = targets}
end

MonsterAI:RegisterMove{
    id = "War Dog Ground Commander: Highest Posthumous Promotion",
    category = "Maneuvers",
    monsters = {"War Dog Ground Commander"},
    abilities = {"Highest Posthumous Promotion"},
    description = "Detonate every collared war dog within 10 when they are spent stragglers beside enemies and no healthy officer would go with them.",
    score = function(self, ai, token, ability)
        local plan, reason = FindHighestPromotionPlan(ai, token, ability)
        if plan == nil then
            return nil, reason
        end
        plan.score = 0.6 + math.min(0.35, plan.gain*0.04)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        Speak(ai, token, "highestPromotion")
        local range = ability:GetRange(token.properties)
        local victims = {}
        for _,other in ipairs(FriendlyWarDogs(token)) do
            if other.charid ~= token.charid and MonsterAI.TargetDistance(token, other) <= range then
                victims[#victims+1] = other
            end
        end
        ExecuteDetonation(ai, token, victims, function()
            ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        end)
    end,
}

MonsterAI:RegisterTrigger{
    id = "War Dog Ground Commander: End Effect",
    monsters = {"War Dog Ground Commander"},
    abilityGuids = {groundCommanderEndEffectGuid},
    abilities = {"End Effect"},
    description = "Leave End Effect to the Director while worth paying for; dismiss it when the 5 damage would leave the commander at 10 Stamina or less.",
    handler = function(ai, token, triggerInfo)
        if token.properties:CurrentHitpoints() <= 15 then
            return {dismiss = true}
        end
        --Its purge opens a choose-the-effect dialog with no AI path, so an AI
        --accept stalls the cast until it is abandoned. nil = the Director's call.
        return nil
    end,
}

--Final Orders: the ally then dies, so the commander only gives the order to
--one who is dying anyway. Its movement and free strike are prompted on that
--ally, so the AI holds its control until the order has resolved.
local function HoldControlUntilIdle(ai, token)
    local info = ai:BeginTokenControl(token)
    dmhub.Coroutine(function()
        local deadline = dmhub.Time() + 60
        local idleSince = nil
        coroutine.yield(0.5)
        while dmhub.Time() < deadline do
            if ActivatedAbility.CountActiveCasts() == 0 then
                idleSince = idleSince or dmhub.Time()
                if dmhub.Time() - idleSince >= 1 then
                    break
                end
            else
                idleSince = nil
            end
            coroutine.yield(0.1)
        end
        pcall(function()
            ai:EndTokenControl(token, info)
        end)
    end)
end

local function FinalOrdersSubject(triggerInfo)
    for _,charid in ipairs(triggerInfo.targets or {}) do
        --GetCharacterById, not GetTokenById: the dying ally may already have
        --been taken off the map.
        local subject = dmhub.GetCharacterById(charid)
        if subject ~= nil and subject.valid and subject.properties ~= nil then
            return subject
        end
    end
end

MonsterAI:RegisterTrigger{
    id = "War Dog Ground Commander: Final Orders",
    monsters = {"War Dog Ground Commander"},
    abilityGuids = {finalOrdersGuid},
    abilities = {"Final Orders"},
    description = "Order an ally who is being killed to move and free strike before dying; never spend a living ally on it.",
    handler = function(ai, token, triggerInfo)
        local subject = FinalOrdersSubject(triggerInfo)
        --A dying minion is often already off the map (Monster Death removes
        --it at once), and a removed token is no one's friend; the trigger only
        --offers allies, so a monster subject is one of ours.
        if subject == nil or subject.playerControlled
            or not (subject:IsFriend(token) or subject.properties:IsMonster()) then
            return {dismiss = true}
        end
        local dying = subject.properties:IsDead() or subject.properties:CurrentHitpoints() <= 0
            or subject.properties:try_get("minionDead", false) == true
        if not dying then
            return {dismiss = true}
        end
        --Not for minions: the raised minion still owes its squad's death, and
        --its granted free strike then waits on that confirmation until the
        --trigger times out.
        if IsMinion(subject) then
            return {dismiss = true}
        end
        HoldControlUntilIdle(ai, subject)
        ai._tmp_warDogFinalOrders = subject.charid
        return {activate = true}
    end,
}

--Where a war dog under final orders (or any granted move) should end up: next
--to as many enemies as possible, so its free strike lands and its collar
--catches the most.
local function BestCollarSquare(token, range, enemies, flags)
    local best = nil
    local currentAdjacent = AdjacentEnemiesAt(enemies, token.loc)
    for _,info in pairs(token:CalculatePathfindingArea(range*10, flags or {})) do
        if info.loc ~= nil and LandingIsFree(token, info.loc) then
            local adjacent = AdjacentEnemiesAt(enemies, info.loc)
            local utility = adjacent - (info.cost or 0)*0.001
            if adjacent > 0 and (best == nil or utility > best.utility) then
                best = {loc = info.loc, adjacent = adjacent, utility = utility}
            end
        end
    end
    if best == nil or best.adjacent <= currentAdjacent then
        return nil
    end
    return best
end

--The order itself arrives on the dying ally as a confirm-or-skip prompt.
MonsterAI:RegisterPrompt{
    prompts = {"War Dog Ground Commander:Move Speed and Make Free Strike"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return {targets = {{token = casterToken}}}
    end,
}

local finalOrdersMovePrompts = {}
for _,monsterType in ipairs(warDogMonsters) do
    finalOrdersMovePrompts[#finalOrdersMovePrompts+1] = monsterType .. ":Move Speed"
    finalOrdersMovePrompts[#finalOrdersMovePrompts+1] = monsterType .. ":Move"
end

MonsterAI:RegisterPrompt{
    prompts = finalOrdersMovePrompts,
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        local best = BestCollarSquare(casterToken, range, HostileCreatures(casterToken))
        if best == nil then
            return {targets = {}}
        end
        casterToken:MarkMovementArrow(best.loc, {straightline = false, ignorecreatures = false})
        MonsterAI.Sleep(movementPause)
        casterToken:ClearMovementArrow()
        return {targets = {{loc = best.loc}}}
    end,
}

--------------------------------------------------------------------------------
-- Ground Commander villain actions.
--------------------------------------------------------------------------------

local function AlliesInBurst(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local result = {}
    for _,ally in ipairs(ai.allyTokens or {}) do
        if LiveCreature(ally) and ally.charid ~= token.charid and not ally.playerControlled
            and MonsterAI.TargetDistance(token, ally) <= range
            and ability:TargetPassesFilter(token, ally, {}) then
            result[#result+1] = ally
        end
    end
    --Non-minions act first; their attacks matter more and they open space.
    table.sort(result, function(a, b)
        return cond(IsMinion(a), 1, 0) < cond(IsMinion(b), 1, 0)
    end)
    return result
end

--The charge a granted Charge main action makes: the cheapest straight-line
--route to a square from which a melee free strike reaches an enemy.
local function FindGrantedCharge(ai, actor)
    local options = FreeStrikeOptions(actor, {melee = true})
    if #options == 0 then
        return nil
    end
    local speed = actor.properties:CurrentMovementSpeed() or 0
    local range = options[1].planning:GetRange(actor.properties)
    local mover = ai:GetMovementToken(actor)
    local best = nil
    for _,enemy in ipairs(HostileCreatures(actor)) do
        if MonsterAI.TargetDistance(actor, enemy) <= speed + range then
            local probe = ai:ChargeProbe(mover, enemy, speed, range)
            if probe ~= nil then
                local utility = BullyTargetScore(enemy, 0) - (probe.cost or 0)*0.001
                if best == nil or utility > best.utility then
                    best = {dest = probe.dest, target = enemy, option = options[1], utility = utility}
                end
            end
        end
    end
    return best
end

MonsterAI:RegisterVillainAction{
    id = "War Dog Ground Commander: Combined Arms",
    monsters = {"War Dog Ground Commander"},
    abilities = {"Combined Arms"},
    description = "Every ally within 10 makes a ranged free strike, then charges.",
    score = function(self, ai, token, ability, context)
        local allies = AlliesInBurst(ai, token, ability)
        local attackers = 0
        for _,ally in ipairs(allies) do
            local shot = BestFreeStrikeFrom(ai, ally, ally.loc, FreeStrikeOptions(ally, {ranged = true}))
            if shot ~= nil or FindGrantedCharge(ai, ally) ~= nil then
                attackers = attackers + 1
            end
        end
        if attackers == 0 then
            return nil, "no ally within 10 can shoot or charge"
        end
        return {score = math.min(1, 0.5 + attackers*0.06), attackers = attackers}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local allies = AlliesInBurst(ai, token, ability)
        Speak(ai, token, "combinedArms")
        ActivateWithBehaviors(ai, token, ability, {}, {})
        for _,ally in ipairs(allies) do
            if LiveCreature(ally) then
                local ok, err = ai:RunWithTokenControl(ally, function()
                    local shot = BestFreeStrikeFrom(ai, ally, ally.loc, FreeStrikeOptions(ally, {ranged = true}))
                    ExecuteFreeStrike(ai, ally, shot)
                    if not LiveCreature(ally) then
                        return
                    end
                    local charge = FindGrantedCharge(ai, ally)
                    if charge ~= nil then
                        local moved = ai:ExecuteChargeMovement(ally, charge.dest, true)
                        if moved and LiveCreature(ally) and LiveCreature(charge.target) then
                            local strike = BestFreeStrikeFrom(ai, ally, ally.loc,
                                FreeStrikeOptions(ally, {melee = true}), nil, charge.target)
                                or BestFreeStrikeFrom(ai, ally, ally.loc, FreeStrikeOptions(ally, {melee = true}))
                            ExecuteFreeStrike(ai, ally, strike)
                        end
                    end
                end)
                if not ok then
                    print(string.format("AI:: Combined Arms failed for %s: %s", ally.name or ally.charid, tostring(err)))
                end
            end
        end
    end,
}

--The enemy most allies can reach and free strike this turn.
local function FindMakeAnExamplePlan(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local best = nil
    for _,enemy in ipairs(LiveEnemies(ai)) do
        if MonsterAI.TargetDistance(token, enemy) <= range
            and ability:TargetPassesFilter(token, enemy, {}) and CanSee(token, enemy) then
            local strikers = {}
            for _,ally in ipairs(ai.allyTokens or {}) do
                if LiveCreature(ally) and ally.charid ~= token.charid and not ally.playerControlled
                    and MonsterAI.TargetDistance(ally, enemy) <= 5 then
                    local approach = FindFreeStrikeApproach(ai, ally, enemy,
                        ally.properties:CurrentMovementSpeed() or 0)
                    if approach ~= nil then
                        strikers[#strikers+1] = {token = ally, approach = approach}
                    end
                end
            end
            local utility = #strikers + (1 - StaminaFraction(enemy))
            if #strikers > 0 and (best == nil or utility > best.utility) then
                best = {target = enemy, strikers = #strikers, utility = utility}
            end
        end
    end
    return best
end


MonsterAI:RegisterVillainAction{
    id = "War Dog Ground Commander: Make an Example of Them",
    monsters = {"War Dog Ground Commander"},
    abilities = {"Make an Example of Them"},
    description = "Single out the enemy the most allies can converge on; each ally within 5 moves in and free strikes them.",
    score = function(self, ai, token, ability, context)
        local plan = FindMakeAnExamplePlan(ai, token, ability)
        if plan == nil then
            return nil, "no enemy within 10 has an ally able to reach and strike them"
        end
        return {score = math.min(1, 0.5 + plan.strikers*0.1), target = plan.target}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local plan = FindMakeAnExamplePlan(ai, token, ability)
        if plan == nil then
            return
        end
        local target = plan.target
        Speak(ai, token, "makeAnExample")
        --Keeps the frightened rider; the allies' moves and strikes are driven below.
        ActivateWithBehaviors(ai, token, ability, WithoutInvokes(ability), {{token = target}},
            {sleep = abilityPause})
        for _,ally in ipairs(ai.allyTokens or {}) do
            if LiveCreature(ally) and LiveCreature(target) and ally.charid ~= token.charid
                and not ally.playerControlled and MonsterAI.TargetDistance(ally, target) <= 5 then
                local approach = FindFreeStrikeApproach(ai, ally, target,
                    ally.properties:CurrentMovementSpeed() or 0)
                if approach ~= nil then
                    local ok, err = ai:RunWithTokenControl(ally, function()
                        MoveCinematically(ai, ally, approach.loc)
                        local strike = BestFreeStrikeFrom(ai, ally, ally.loc, FreeStrikeOptions(ally), nil, target)
                        ExecuteFreeStrike(ai, ally, strike)
                    end)
                    if not ok then
                        print(string.format("AI:: Make an Example failed for %s: %s", ally.name or ally.charid, tostring(err)))
                    end
                end
            end
        end
    end,
}

--Each ally shifts up to 2 next to a different ungrabbed enemy and grabs them.
local function PlanClaimThem(ai, token, ability)
    local allies = AlliesInBurst(ai, token, ability)
    local enemies = {}
    for _,enemy in ipairs(LiveEnemies(ai)) do
        if not enemy.properties:HasNamedCondition("Grabbed") then
            enemies[#enemies+1] = enemy
        end
    end
    local claimed = {}
    local reserved = {}
    local plans = {}
    for _,ally in ipairs(allies) do
        local grab = FindAbility(ally, "Grab")
        if grab ~= nil then
            local grabRange = grab:GetRange(ally.properties)
            local best = nil
            for _,info in pairs(ally:CalculatePathfindingArea(20, {"shift"})) do
                if info.loc ~= nil and (LocKey(info.loc) == LocKey(ally.loc) or LandingIsFree(ally, info.loc, reserved)) then
                    for _,enemy in ipairs(enemies) do
                        if not claimed[enemy.charid] and ai:TargetDistanceFromLoc(ally, enemy, info.loc) <= grabRange then
                            --Grabbing the weakest pins down the most dangerous-to-leave.
                            local utility = BullyTargetScore(enemy, 0) - (info.cost or 0)*0.001
                            if best == nil or utility > best.utility then
                                best = {ally = ally, loc = info.loc, target = enemy, grab = grab, utility = utility}
                            end
                        end
                    end
                end
            end
            if best ~= nil then
                claimed[best.target.charid] = true
                ReserveLanding(ally, best.loc, reserved)
                plans[#plans+1] = best
            end
        end
    end
    return plans
end

local function ExecuteGrantedShift(ai, actor, loc, distance)
    if not LiveCreature(actor) or loc == nil or ai:MovementTokenIsAtLoc(actor, loc) then
        return
    end
    local shift = MCDMUtils.GetStandardAbility("Shift"):MakeTemporaryClone()
    shift.range = distance
    shift.actionResourceId = "none"
    shift.targetFilter = ""
    ai:ExecuteAbility(actor, shift, {{loc = loc}}, {sleep = grantedActionPause})

    --The shift's cast finishes before the token has walked there; whatever
    --follows (a free strike, a grab) is planned from where it really stands.
    local mover = ai:GetMovementToken(actor)
    local deadline = dmhub.Time() + 5
    while mover.valid and mover.isMoving and dmhub.Time() < deadline do
        coroutine.yield(0.05)
    end
    ai:InvalidatePlanningMemo()
end

MonsterAI:RegisterVillainAction{
    id = "War Dog Ground Commander: Claim Them for the Body Banks",
    monsters = {"War Dog Ground Commander"},
    abilities = {"Claim Them for the Body Banks"},
    description = "Every ally within 10 shifts 2 and grabs a different enemy; enemies take a bane on escaping grabs for the encounter.",
    score = function(self, ai, token, ability, context)
        local plans = PlanClaimThem(ai, token, ability)
        if #plans == 0 then
            return nil, "no ally can shift next to an ungrabbed enemy"
        end
        return {score = math.min(1, 0.5 + #plans*0.1), grabs = #plans}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local plans = PlanClaimThem(ai, token, ability)
        Speak(ai, token, "claimThem")
        --Keeps the enemies' bane on Escape Grab; the allies' shifts and grabs
        --are driven below.
        ActivateWithBehaviors(ai, token, ability, WithoutInvokes(ability), nil, {sleep = abilityPause})
        for _,plan in ipairs(plans) do
            if LiveCreature(plan.ally) and LiveCreature(plan.target) then
                local ok, err = ai:RunWithTokenControl(plan.ally, function()
                    ExecuteGrantedShift(ai, plan.ally, plan.loc, 2)
                    if LiveCreature(plan.ally) and LiveCreature(plan.target)
                        and MonsterAI.TargetDistance(plan.ally, plan.target) <= plan.grab:GetRange(plan.ally.properties) then
                        local grab = DeepCopy(plan.grab)
                        grab.actionResourceId = "none"
                        ai:ExecuteAbility(plan.ally, grab, {{token = plan.target}}, {sleep = grantedActionPause})
                    end
                end)
                if not ok then
                    print(string.format("AI:: Claim Them grab failed for %s: %s", plan.ally.name or plan.ally.charid, tostring(err)))
                end
            end
        end
    end,
}

--------------------------------------------------------------------------------
-- Start-of-turn War Dog Malice features.
--------------------------------------------------------------------------------

local function IsHumanoidCorpse(token)
    if token == nil or token.properties == nil then
        return false
    end
    if HasKeyword(token, "Humanoid") then
        return true
    end
    --Every hero ancestry is humanoid.
    return not token.properties:IsMonster()
end

--Squares of humanoid corpses on the war dog's floor: corpse objects left by
--dead monsters, and fallen heroes still lying where they died.
local function HumanoidCorpsesNear(token, radius)
    local count = 0
    local floor = game.GetFloor(token.floorid)
    if floor ~= nil then
        for _,obj in pairs(floor.objects or {}) do
            local corpse = obj:GetComponent("Corpse")
            if corpse ~= nil and corpse.properties ~= nil then
                local dead = dmhub.GetCharacterById(corpse.properties.charid)
                if IsHumanoidCorpse(dead)
                    and math.max(math.abs(obj.x - token.pos.x), math.abs(obj.y - token.pos.y)) <= radius + 0.5 then
                    count = count + 1
                end
            end
        end
    end
    for _,other in ipairs(dmhub.allTokens) do
        if other.valid and other.properties ~= nil and other.floorid == token.floorid
            and other.properties:IsDead() and IsHumanoidCorpse(other)
            and token:Distance(other) <= radius then
            count = count + 1
        end
    end
    return count
end

--How close a corpse must be for Reconstitute.
local reconstituteCorpseRange = 5

MonsterAI:RegisterMaliceAbility{
    id = "War Dog Malice: Reconstitute",
    monsterGroups = warDogGroup,
    abilities = {"Reconstitute"},
    description = "Spend 3 Malice to heal a badly hurt acting non-minion war dog from a humanoid corpse within 5 squares, when it would use most of the healing.",
    score = function(self, ai, token, ability, context)
        local best = nil
        for _,actor in ipairs(context.actingTokens or {}) do
            if IsWarDog(actor) and not IsMinion(actor) and actor:IsFriend(token)
                and FindAbility(actor, "Reconstitute") ~= nil then
                local heal = 5*(tonumber(actor.properties:try_get("cr")) or 1)
                local missing = MissingStamina(actor)
                if missing >= heal*0.8 and StaminaFraction(actor) <= 0.6
                    and HumanoidCorpsesNear(actor, reconstituteCorpseRange) > 0 then
                    local value = math.min(missing, heal)/MaxStamina(actor)
                    if best == nil or value > best.value then
                        best = {actor = actor, value = value}
                    end
                end
            end
        end
        if best == nil then
            return nil, "no acting war dog is hurt enough with a humanoid corpse nearby"
        end
        return {
            score = math.min(0.9, 0.66 + best.value*0.5),
            actor = best.actor,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local actor = scoringInfo.actor
        if not LiveCreature(actor) then
            return
        end
        --The healed war dog casts it on itself, which may not be the
        --scheduler's chosen caster.
        local reconstitute = FindAbility(actor, "Reconstitute")
        local caster = actor
        if reconstitute == nil then
            reconstitute = ability
            caster = token
        end
        ai:RunWithTokenControl(caster, function()
            Speak(ai, caster, "reconstitute")
            ai:ExecuteAbility(caster, reconstitute, {{token = caster}}, {sleep = abilityPause})
        end)
    end,
}

--Fire for Effect: which condition. Weakened blunts enemies already fighting
--war dogs; slowed keeps the rest from closing in or getting out of the fire.
local function FireForEffectMode(token, plan, enemies)
    local engaged = 0
    local warDogs = FriendlyWarDogs(token)
    for _,enemy in ipairs(enemies) do
        if enemy:Distance(plan.center) <= 3 then
            for _,warDog in ipairs(warDogs) do
                if MonsterAI.TargetDistance(warDog, enemy) <= 1 then
                    engaged = engaged + 1
                    break
                end
            end
        end
    end
    return cond(engaged*2 >= plan.enemies, 2, 1)
end

--Each creature in the cube is hit, so allies count against it.
local fireForEffectWeights = {enemy = 1, minionAlly = -0.3, ally = -2}

MonsterAI:RegisterMaliceAbility{
    id = "War Dog Malice: Fire for Effect",
    monsterGroups = warDogGroup,
    abilities = {"Fire for Effect"},
    description = "Spend 5 Malice to shell a 4 cube within 10 of an acting war dog when it catches at least three enemies and no healthy officer.",
    score = function(self, ai, token, ability, context)
        local best = nil
        for _,actor in ipairs(context.actingTokens or {}) do
            local actorAbility = IsWarDog(actor) and actor:IsFriend(token) and FindAbility(actor, "Fire for Effect") or nil
            if actorAbility ~= nil and actorAbility:CanAfford(actor) then
                local plan = FindBestCubePlan(ai, actor, actorAbility, {{loc = actor.loc, cost = 0}},
                    fireForEffectWeights, {mode = 1})
                if plan ~= nil and (best == nil or plan.value > best.plan.value) then
                    best = {actor = actor, plan = plan}
                end
            end
        end
        if best == nil or best.plan.enemies < 3 or best.plan.value < 2.5 then
            return nil, "no cube catches three enemies without allies"
        end
        local mode = FireForEffectMode(token, best.plan, LiveEnemies(ai))
        return {
            score = math.min(0.95, 0.7 + (best.plan.value - 2.5)*0.08),
            actor = best.actor,
            center = best.plan.center,
            enemies = best.plan.enemies,
            mode = mode,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local actor = scoringInfo.actor
        if not LiveCreature(actor) then
            return
        end
        --Cast by whichever acting war dog had the best cube in range.
        local actorAbility = FindAbility(actor, "Fire for Effect")
        local caster = actor
        if actorAbility == nil then
            actorAbility = ability
            caster = token
        end
        ai:RunWithTokenControl(caster, function()
            Speak(ai, caster, "fireForEffect")
            local symbols = {mode = scoringInfo.mode}
            ExecuteCubePlan(ai, caster, actorAbility:SwitchModes(scoringInfo.mode), scoringInfo.center, symbols)
        end)
    end,
}

--Fodder Run: each minion that can get next to an enemy shifts there, makes a
--free strike, and is reduced to 0 Stamina, so its collar goes off there too.
--Minions who cannot reach anyone simply stay out of it and live.
local function PlanFodderRun(ai, token, context)
    local enemies = {}
    for _,enemy in ipairs(context.enemyTokens or {}) do
        if LiveCreature(enemy) then
            enemies[#enemies+1] = enemy
        end
    end
    if #enemies == 0 then
        return nil
    end
    local acting = {}
    for _,actor in ipairs(context.actingTokens or {}) do
        acting[actor.charid] = true
    end

    local minions = {}
    for _,other in ipairs(FriendlyWarDogs(token)) do
        if IsMinion(other) then
            local nearest = 999
            for _,enemy in ipairs(enemies) do
                nearest = math.min(nearest, MonsterAI.TargetDistance(other, enemy))
            end
            local speed = other.properties:CurrentMovementSpeed() or 0
            if nearest <= speed + 1 then
                minions[#minions+1] = {token = other, nearest = nearest, speed = speed}
            end
        end
    end
    table.sort(minions, function(a, b) return a.nearest < b.nearest end)

    local reserved = {}
    local plans = {}
    local total = 0
    for _,entry in ipairs(minions) do
        local minion = entry.token
        local best = nil
        for _,info in pairs(minion:CalculatePathfindingArea(entry.speed*10, {"shift"})) do
            local loc = info.loc
            if loc ~= nil and (LocKey(loc) == LocKey(minion.loc) or LandingIsFree(minion, loc, reserved)) then
                local adjacent = AdjacentEnemiesAt(enemies, loc)
                if adjacent > 0 then
                    local utility = adjacent*minionCollarDamage + freeStrikeValue - (info.cost or 0)*0.001
                    if best == nil or utility > best.utility then
                        best = {loc = loc, adjacent = adjacent, utility = utility}
                    end
                end
            end
        end
        if best ~= nil then
            --A minion acting this turn would otherwise make its own strike now.
            local keep = KeepValue(minion, true) + cond(acting[minion.charid], minionStrikeValue, 0)
            local gain = best.utility - keep
            if gain > 0 then
                ReserveLanding(minion, best.loc, reserved)
                plans[#plans+1] = {token = minion, loc = best.loc, adjacent = best.adjacent, gain = gain}
                total = total + gain
            end
        end
    end
    return plans, total
end

local fodderRunMinimumMinions = 3
local fodderRunMinimumGain = 6

MonsterAI:RegisterMaliceAbility{
    id = "War Dog Malice: Fodder Run",
    monsterGroups = warDogGroup,
    abilities = {"Fodder Run"},
    description = "Spend 7 Malice to send at least three minions who are worth more exploded than alive running at the enemy to strike and detonate.",
    score = function(self, ai, token, ability, context)
        local plans, total = PlanFodderRun(ai, token, context)
        if plans == nil or #plans < fodderRunMinimumMinions or total < fodderRunMinimumGain then
            return nil, string.format("only %d minions gain %.1f by running", plans ~= nil and #plans or 0, total or 0)
        end
        return {
            score = math.min(0.95, 0.68 + (total - fodderRunMinimumGain)*0.03),
            runners = #plans,
            gain = total,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local plans = PlanFodderRun(ai, token, context)
        if plans == nil or #plans == 0 then
            return
        end
        Speak(ai, token, "fodderRun")
        --Pay for the feature, then drive each runner directly.
        local area = dmhub.CalculateShape{
            shape = "map",
            token = token,
        }
        ActivateWithBehaviors(ai, token, ability, {}, {}, {
            sleep = stationaryPause,
            symbols = {targetArea = area},
            targetArea = area,
        })

        for _,plan in ipairs(plans) do
            local minion = plan.token
            if LiveCreature(minion) then
                local ok, err = ai:RunWithTokenControl(minion, function()
                    ExecuteGrantedShift(ai, minion, plan.loc, minion.properties:CurrentMovementSpeed() or 0)
                    if not LiveCreature(minion) then
                        return
                    end
                    local strike = BestFreeStrikeFrom(ai, minion, minion.loc, FreeStrikeOptions(minion))
                    if strike == nil then
                        --Only a minion who strikes is spent.
                        ai:LogDecision("FODDER RUN", {
                            actor = ai.TokenLogName(minion),
                            reason = "no free strike from where the run ended",
                            result = "minion kept",
                        })
                        return
                    end
                    ExecuteFreeStrike(ai, minion, strike)
                    if LiveCreature(minion) then
                        --Reduced to 0 Stamina, which sets off its loyalty collar.
                        local spend = ActivatedAbility.Create{
                            name = "Fodder Run",
                            iconid = ability.iconid,
                            display = ability.display,
                            targetType = "self",
                            actionResourceId = "none",
                            behaviors = {ActivatedAbilityDestroyBehavior.new{}},
                        }
                        ExecuteDetonation(ai, minion, {minion}, function()
                            ai:ExecuteAbility(minion, spend, {{token = minion}}, {sleep = grantedActionPause})
                        end)
                    end
                end)
                if not ok then
                    print(string.format("AI:: Fodder Run failed for %s: %s", minion.name or minion.charid, tostring(err)))
                end
            end
        end
    end,
}
