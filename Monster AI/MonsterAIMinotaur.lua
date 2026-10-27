local mod = dmhub.GetModLoading()

--Monster AI for the Minotaur band: the Minotaur elite's own abilities, plus the
--group Malice features every minotaur can call on. The other minotaur stat
--blocks (Sunderer, Gorer, Bully, Lackey, Stampede) fall back to generic AI.

local minotaurMonster = {"Minotaur"}
local minotaurGroup = {"Minotaur"}

local movementPause = 0.6
local abilityPause = 1.0

local primalBayEffectId = "37167b9d-f9ca-49d3-9ea1-001f720c56a2"
local bullRushEffectId = "5f404222-50d8-4777-8754-5e2eccd2d43a"
local cutTheNonsenseEffectId = "a842e886-569c-4753-b8b3-a3281151f4da"

--Bull Rush's speed bonus per Malice step, from the book.
local bullRushSpeedBonus = 4

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject and token.properties ~= nil
        and not token.properties:IsDead()
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

local function FindAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name then
            return ability
        end
    end
end

--Group Malice features only: the Minotaur Stampede's signature strike is also
--named "Bull Rush", and a plain name lookup would return it first.
local function FindMaliceAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name and ability.categorization == "Malice" then
            return ability
        end
    end
end

--pcall: hero properties raise on a read of the monster-only keywords field.
local function IsMinotaur(token)
    if not LiveCreature(token) then
        return false
    end
    local keywords = nil
    pcall(function() keywords = token.properties.keywords end)
    return type(keywords) == "table" and keywords.Minotaur == true
end

--TokensAreFriendly is the allegiance test the AI core uses. IsFriend also
--counts any creature the Director controls, so it calls an unowned hero a friend.
local function IsHostile(token, other)
    return not dmhub.TokensAreFriendly(token, other)
end

local function HostileCreatures(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and IsHostile(token, other) then
            result[#result+1] = other
        end
    end
    return result
end

local function NearestDistance(token, enemies)
    local result = nil
    for _,enemy in ipairs(enemies) do
        local distance = MonsterAI.TargetDistance(token, enemy)
        if result == nil or distance < result then
            result = distance
        end
    end
    return result
end

local function CountWithin(token, enemies, range)
    local result = 0
    for _,enemy in ipairs(enemies) do
        if MonsterAI.TargetDistance(token, enemy) <= range then
            result = result + 1
        end
    end
    return result
end

local function EnemyInSightWithin(token, enemies, range)
    local pierceWalls = token.properties:GetPierceWalls()
    for _,enemy in ipairs(enemies) do
        if MonsterAI.TargetDistance(token, enemy) <= range
            and token:GetLineOfSight(enemy, pierceWalls) > 0 then
            return true
        end
    end
    return false
end

--How far a minotaur strikes: its signature ability's range, else melee 1.
local function StrikeReach(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability:try_get("categorization") == "Signature Ability" then
            return ability:GetRange(token.properties)
        end
    end
    return 1
end

local function StaminaFraction(token)
    return token.properties:CurrentHitpoints() / math.max(1, token.properties:MaxHitpoints())
end

local function MoveCinematically(ai, token, loc)
    if loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc) then
        ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(movementPause)
    end
end

local function DefaultTargetScore(target, edges)
    if target.isObject then
        return 0.1
    end
    return 1 + (edges or 0)*0.1 + MonsterAI.TargetStaminaBias(target)
end

--Goring Horns dazes when the target's Intuition is below the tier's potency
--(0/1/2, one higher while charging). It is only worth 5 Malice when the daze
--can land at tier 2 or better, and never on a creature who is already dazed.
local function GoringHornsWorthIt(target, charging)
    if target.isObject or target.properties:HasNamedCondition("Dazed") then
        return false
    end
    local intuition = target.properties:GetAttribute("inu"):Modifier()
    return intuition < cond(charging, 2, 1)
end

local function GoringHornsTargetScore(target, edges)
    if not GoringHornsWorthIt(target, false) then
        return 0
    end
    return DefaultTargetScore(target, edges)
end

--Goring Horns is a maneuver, so it cannot ride the planner's free charge
--movement (a charge costs the main action). Plan it from a copy without the
--Charge keyword; the cast still uses the real ability.
local function GoringHornsPlanningCopy(ability)
    local copy = DeepCopy(ability)
    if copy.keywords ~= nil then
        copy.keywords.Charge = nil
    end
    return copy
end

--Best enemies for a strike from a square, highest score first, trimmed to the
--ability's target count. Targets scoring 0 or less are dropped.
local function SortedStrikeTargets(ai, token, ability, loc, scorefn)
    local targets = {}
    for _,targetInfo in ipairs(ai:FindValidTargetsOfStrike(token, ability, loc)) do
        if scorefn(targetInfo.token, targetInfo.edges) > 0 then
            targets[#targets+1] = targetInfo
        end
    end
    table.sort(targets, function(a, b)
        return scorefn(a.token, a.edges) > scorefn(b.token, b.edges)
    end)
    table.resize_array(targets, ability:GetNumTargets(token))
    return targets
end

--------------------------------------------------------------------------------
-- Main actions and maneuvers.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Minotaur: Flail and Blade",
    category = "Main Actions",
    monsters = minotaurMonster,
    abilities = {"Flail and Blade"},
    description = "Signature strike on up to two enemies, charging in when that reaches them.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, DefaultTargetScore)
        if loc == nil then
            return nil, "no enemy reachable with Flail and Blade"
        end
        return {score = 1.0 + math.min(0.2, targetScore*0.05), loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        --A planned charge keeps its landing square on the targets, and
        --ExecuteAbility runs the straight-line move before striking.
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, DefaultTargetScore)
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Minotaur: Goring Horns",
    category = "Maneuvers",
    monsters = minotaurMonster,
    abilities = {"Goring Horns"},
    description = "Spend 5 Malice to gore an enemy who is not dazed and whose Intuition lets the daze land.",
    score = function(self, ai, token, ability)
        local planning = GoringHornsPlanningCopy(ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, planning, GoringHornsTargetScore)
        if loc == nil or targetScore <= 0 then
            return nil, "no reachable enemy the daze can land on"
        end
        return {score = 0.85, loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local planning = GoringHornsPlanningCopy(ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, planning, scoringInfo.loc, GoringHornsTargetScore)
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Minotaur: Primal Bay",
    category = "Main Actions",
    monsters = minotaurMonster,
    abilities = {"Primal Bay"},
    description = "Spend 3 Malice on Primal Bay when no enemy can be struck this turn but one will be in reach next turn.",
    score = function(self, ai, token, ability)
        if HasOngoingEffect(token, primalBayEffectId) then
            return nil, "Primal Bay is already active"
        end
        --CanStrikeThisTurn is cheap but optimistic (it ignores whatever blocks a
        --charge), so trust its "no". Only when no enemy is in sight within reach
        --and none is ruled out does Flail and Blade's own exact search decide.
        local nearest = NearestDistance(token, ai.enemyTokens or {})
        if ai:CanStrikeThisTurn(token) then
            local flail = FindAbility(token, "Flail and Blade")
            if flail == nil or EnemyInSightWithin(token, ai.enemyTokens or {}, StrikeReach(token))
                or ai:FindBestMoveToUseStrike(token, flail) ~= nil then
                return nil, "an enemy is in reach; strike instead"
            end
        end
        local speed = token.properties:CurrentMovementSpeed() or 0
        if nearest == nil or nearest > speed*2 + StrikeReach(token) then
            return nil, "no enemy close enough to benefit next turn"
        end
        return {score = 1.1}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:ExecuteAbility(token, ability, {{token = token}}, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Start-of-turn Malice abilities.
--------------------------------------------------------------------------------

--A minotaur Bull Rush helps: nothing in reach at its speed, but something in
--reach with the bonus. Distances are straight-line estimates.
local function BullRushHelps(actor, enemies)
    local nearest = NearestDistance(actor, enemies)
    if nearest == nil then
        return false
    end
    local speed = actor.properties:CurrentMovementSpeed() or 0
    local reach = StrikeReach(actor)
    return nearest > speed + reach and nearest <= speed + bullRushSpeedBonus + reach
end

--Bull Rush buffs one minotaur per 3 Malice spent.
local bullRushMalicePerMinotaur = 3

--The acting minotaurs who can only reach an enemy with Bull Rush's bonus, as
--many as the current Malice pays for. The first one can afford the base cost.
local function BullRushPlan(context)
    local enemies = context.enemyTokens or {}
    local caster = nil
    local ability = nil
    local minotaurs = {}
    for _,actor in ipairs(context.actingTokens or {}) do
        if IsMinotaur(actor) and not HasOngoingEffect(actor, bullRushEffectId)
            and BullRushHelps(actor, enemies) then
            local actorAbility = FindMaliceAbility(actor, "Bull Rush")
            if caster == nil and actorAbility ~= nil and actorAbility:CanAfford(actor) then
                caster = actor
                ability = actorAbility
                table.insert(minotaurs, 1, actor)
            else
                minotaurs[#minotaurs+1] = actor
            end
        end
    end
    if caster == nil then
        return nil
    end
    local affordable = math.floor((CharacterResource.GetMalice() or 0) / bullRushMalicePerMinotaur)
    table.resize_array(minotaurs, math.max(1, math.min(#minotaurs, affordable)))
    return {caster = caster, ability = ability, minotaurs = minotaurs}
end

MonsterAI:RegisterMaliceAbility{
    id = "Minotaur Malice: Bull Rush",
    monsterGroups = minotaurGroup,
    abilities = {"Bull Rush"},
    description = "Spend 3 Malice per acting minotaur who can only reach an enemy with Bull Rush's speed bonus, buffing them all in one cast.",
    score = function(self, ai, token, ability, context)
        local plan = BullRushPlan(context)
        if plan == nil then
            return nil, "no acting minotaur needs the speed"
        end
        --Not "targets": the decision log reads that field as a target list.
        return {
            score = math.min(0.84, 0.72 + 0.04*(#plan.minotaurs - 1)),
            buffing = #plan.minotaurs,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local plan = BullRushPlan(context)
        if plan == nil then
            return
        end
        local targets = {}
        for _,minotaur in ipairs(plan.minotaurs) do
            targets[#targets+1] = {token = minotaur}
        end

        --Its target count is "1 + Charges", which the AI would read as 1, so set it
        --on a copy. AI casts only pay the base 3 Malice; the rest is paid below.
        local rush = plan.ability:MakeTemporaryClone()
        rush.numTargets = tostring(#targets)
        local rushed = false
        rush.OnFinishCast = function(_, options)
            rushed = not options.abort and not options.atexit
        end
        ai:RunWithTokenControl(plan.caster, function()
            ai:ExecuteAbility(plan.caster, rush, targets, {sleep = abilityPause})
        end)

        local extra = (#targets - 1)*bullRushMalicePerMinotaur
        if rushed and extra > 0 then
            local malice = CharacterResource.GetMalice()
            CharacterResource.SetMalice(math.max(0, malice - extra),
                string.format("Bull Rush: %d extra minotaurs", #targets - 1))
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Minotaur Malice: Cut the Nonsense",
    monsterGroups = minotaurGroup,
    abilities = {"Cut the ... Nonsense!"},
    description = "Spend 5 Malice to halve damage on an acting minotaur hemmed in by enemies, or hurt with an enemy close.",
    score = function(self, ai, token, ability, context)
        local enemies = context.enemyTokens or {}
        local best = nil
        for _,actor in ipairs(context.actingTokens or {}) do
            local actorAbility = IsMinotaur(actor) and FindMaliceAbility(actor, "Cut the ... Nonsense!") or nil
            if actorAbility ~= nil and actorAbility:CanAfford(actor)
                and not HasOngoingEffect(actor, cutTheNonsenseEffectId) then
                local near = CountWithin(actor, enemies, 3)
                local hurt = 1 - StaminaFraction(actor)
                local value = nil
                if near >= 2 then
                    value = 0.7 + math.min(0.12, (near - 2)*0.04) + hurt*0.15
                elseif near >= 1 and hurt >= 0.5 then
                    value = 0.68 + hurt*0.1
                end
                if value ~= nil and (best == nil or value > best.score) then
                    best = {score = math.min(0.9, value), actor = actor}
                end
            end
        end
        if best == nil then
            return nil, "no acting minotaur is pressed hard enough"
        end
        return best
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local actor = scoringInfo.actor
        if not LiveCreature(actor) then
            return
        end
        --Self-targeted, so the minotaur who benefits must cast it.
        local actorAbility = FindMaliceAbility(actor, "Cut the ... Nonsense!") or ability
        ai:RunWithTokenControl(actor, function()
            ai:ExecuteAbility(actor, actorAbility, {{token = actor}}, {sleep = abilityPause})
        end)
    end,
}

--------------------------------------------------------------------------------
-- Retaliatory Strike: charge the creature who hurt the minotaur.
--------------------------------------------------------------------------------

--The enemy each minotaur is retaliating against, by minotaur charid. Set when
--the trigger is accepted; read by the Charge and strike prompts that follow.
--Each entry is stamped with the time it was set, so one left behind by an
--aborted retaliation goes stale. Not the turn: the core waits up to 45 seconds
--for the triggering cast to finish, and the turn can change in that time.
local g_retaliationTargets = {}
local retaliationWindowSeconds = 60

local function SetRetaliationTarget(token, target)
    if target == nil then
        g_retaliationTargets[token.charid] = nil
    else
        g_retaliationTargets[token.charid] = {charid = target.charid, time = dmhub.Time()}
    end
end

local function RetaliationTargetId(token)
    local entry = g_retaliationTargets[token.charid]
    if entry == nil then
        return nil
    end
    if dmhub.Time() - entry.time > retaliationWindowSeconds then
        g_retaliationTargets[token.charid] = nil
        return nil
    end
    return entry.charid
end

--Where the retaliatory charge lands. An attacker already within reach is a
--charge of zero squares, landing where the minotaur stands.
local function RetaliationCharge(ai, token, target)
    local speed = token.properties:CurrentMovementSpeed() or 0
    local reach = StrikeReach(token)
    if MonsterAI.TargetDistance(token, target) > speed + reach then
        return nil
    end
    local mover = ai:GetMovementToken(token)
    if MonsterAI.TargetDistance(token, target) <= reach then
        return {dest = mover.loc, chargeDist = 0}
    end
    local probe = ai:ChargeProbe(mover, target, speed, reach)
    if probe == nil or probe.chargeDist <= 0 then
        return nil
    end
    return probe
end

MonsterAI:RegisterTrigger{
    id = "Minotaur: Retaliatory Strike",
    monsters = minotaurMonster,
    abilities = {"Retaliatory Strike"},
    description = "Charge an enemy who damaged the minotaur whenever a straight-line charge reaches them.",
    handler = function(ai, token, triggerInfo)
        SetRetaliationTarget(token, nil)
        for _,charid in ipairs(triggerInfo.targets or {}) do
            local attacker = dmhub.GetTokenById(charid)
            if attacker ~= nil and LiveCreature(attacker) and IsHostile(token, attacker)
                and RetaliationCharge(ai, token, attacker) ~= nil then
                SetRetaliationTarget(token, attacker)
                return {activate = true}
            end
        end
        return {dismiss = true}
    end,
}

--Retaliatory Strike offers the Charge action through an ability chooser.
--Pick Charge and land where the strike reaches the attacker.
MonsterAI:RegisterPrompt{
    id = "Minotaur: Retaliatory Charge",
    prompts = {"Minotaur:Invoked Ability"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local targetid = RetaliationTargetId(casterToken)
        if targetid == nil then
            return nil
        end
        local charge = nil
        for _,synth in ipairs(abilityClone:SynthesizeAbilities(casterToken.properties) or {}) do
            if synth.name == "Charge" then
                charge = synth
            end
        end
        if charge == nil then
            return nil
        end
        local target = dmhub.GetTokenById(targetid)
        local probe = LiveCreature(target) and RetaliationCharge(ai, casterToken, target) or nil
        if probe == nil then
            SetRetaliationTarget(casterToken, nil)
            return {targets = {}}
        end
        return {abilityOverride = charge, targets = {{loc = probe.dest}}}
    end,
}

--The strike at the end of the retaliatory charge, against the attacker only.
MonsterAI:RegisterPrompt{
    id = "Minotaur: Retaliatory Attack",
    prompts = {"Minotaur:Attack when Charging"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local targetid = RetaliationTargetId(casterToken)
        if targetid == nil then
            return nil
        end
        SetRetaliationTarget(casterToken, nil)

        local target = dmhub.GetTokenById(targetid)
        if not LiveCreature(target) then
            return {targets = {}}
        end

        local byName = {}
        for _,synth in ipairs(abilityClone:SynthesizeAbilities(casterToken.properties) or {}) do
            byName[synth.name] = synth
        end
        --Goring Horns gains +1 potency on a charge, but costs 5 Malice.
        local horns = FindAbility(casterToken, "Goring Horns")
        local chosen = byName["Flail and Blade"] or byName["Melee Free Strike"]
        if byName["Goring Horns"] ~= nil and horns ~= nil and horns:CanAfford(casterToken)
            and GoringHornsWorthIt(target, true) then
            chosen = byName["Goring Horns"]
        end
        if chosen == nil then
            return nil
        end

        if MonsterAI.TargetDistance(chosen:GetRangeSource(casterToken), target) > chosen:GetRange(casterToken.properties)
            or not chosen:TargetPassesFilter(casterToken, target, symbols or {}) then
            return {targets = {}}
        end
        return {abilityOverride = chosen, targets = {{token = target}}}
    end,
}

--------------------------------------------------------------------------------
-- Flail and Blade's shift, and Cut the ... Nonsense!'s Knockback.
--------------------------------------------------------------------------------

--True when nothing but objects stands where the token would land. A shift may
--pass through an ally's square but cannot end in one, and a size 2 minotaur
--covers four squares.
local function LandingIsFree(token, loc)
    if loc == nil or not loc.valid then
        return false
    end
    for _,occupied in ipairs(token:LocsOccupyingWhenAt(loc)) do
        for _,other in ipairs(dmhub.GetTokensAtLoc(occupied) or {}) do
            if other.valid and other.charid ~= token.charid and not other.isObject then
                return false
            end
        end
    end
    return true
end

--After Flail and Blade, shift to stay within reach of an enemy (ideally one
--Goring Horns can daze) without ending boxed in by adjacent enemies.
MonsterAI:RegisterPrompt{
    id = "Minotaur: Flail and Blade Shift",
    prompts = {"Minotaur:Shift"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties)
        local reach = StrikeReach(casterToken)
        local enemies = HostileCreatures(casterToken)
        if #enemies == 0 then
            return {targets = {}}
        end
        local horns = FindAbility(casterToken, "Goring Horns")
        local hornsReady = horns ~= nil and horns:CanAfford(casterToken)

        local function Value(loc, cost)
            local inReach = 0
            local hornsTarget = false
            local adjacent = 0
            local nearest = nil
            for _,enemy in ipairs(enemies) do
                local distance = ai:TargetDistanceFromLoc(casterToken, enemy, loc)
                if distance <= reach then
                    inReach = inReach + 1
                    if hornsReady and GoringHornsWorthIt(enemy, false) then
                        hornsTarget = true
                    end
                end
                if distance <= 1 then
                    adjacent = adjacent + 1
                end
                if nearest == nil or distance < nearest then
                    nearest = distance
                end
            end
            return cond(inReach > 0, 3, 0) + math.min(inReach, 2)*0.5 + cond(hornsTarget, 1, 0)
                - adjacent*0.75 - (nearest or 0)*0.05 - (cost or 0)*0.001
        end

        local currentValue = Value(casterToken.loc, 0)
        local best = nil
        for _,info in pairs(casterToken:CalculatePathfindingArea(range*10, {"shift"})) do
            if info.loc.str ~= casterToken.loc.str and LandingIsFree(casterToken, info.loc) then
                local value = Value(info.loc, info.cost)
                if value > currentValue and (best == nil or value > best.value) then
                    best = {loc = info.loc, value = value}
                end
            end
        end

        if best == nil then
            --Staying put is best; decline the optional shift.
            return {targets = {}}
        end
        casterToken:MarkMovementArrow(best.loc, {straightline = true, ignorecreatures = false})
        MonsterAI.Sleep(movementPause)
        casterToken:ClearMovementArrow()
        return {targets = {{loc = best.loc}}}
    end,
}

--A free triggered Knockback whenever an enemy comes adjacent; always worth it.
MonsterAI:RegisterTrigger{
    id = "Minotaur: Cut the Nonsense Knockback",
    abilities = {"Cut the ... Nonsense!"},
    description = "Knock back each enemy who comes adjacent while Cut the ... Nonsense! is active.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}
