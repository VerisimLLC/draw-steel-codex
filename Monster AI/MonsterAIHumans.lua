local mod = dmhub.GetModLoading()

local humanGroup = {"Human"}
local deathCultistMonster = {"Human Death Cultist"}

local movementPause = 0.6
local abilityPause = 1.0

local speechLines = {
    riseMyMinions = {"Rise! Your work is not done!", "Death is no excuse!"},
    drainingScythe = {"Your life is mine!"},
}

local deathScytheDrainMode = 2
local deathScytheDrainCost = 2
--The drain heals half the damage dealt (3-6), so it is only worth it once the
--cultist is missing at least this much Stamina.
local deathScytheDrainMinimumMissing = 5

local riseMyMinionsRange = 5

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject and token.properties ~= nil
        and not token.properties:IsDead()
end

--Not IsFriend: it counts every Director-controlled creature, so it calls an unowned hero a friend.
local function IsHostile(token, other)
    return not dmhub.TokensAreFriendly(token, other)
end

local function FindAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name then
            return ability
        end
    end
end

--A human's own ability can share a Malice feature's name; only the Malice one counts.
local function FindMaliceAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name and ability.categorization == "Malice" then
            return ability
        end
    end
end

--pcall: hero properties raise on a read of the monster-only keywords field.
local function HasKeyword(token, keyword)
    local keywords = nil
    pcall(function() keywords = token.properties.keywords end)
    return type(keywords) == "table" and keywords[keyword] == true
end

local function IsHuman(token)
    return LiveCreature(token) and HasKeyword(token, "Human")
end

local function IsMinion(token)
    return token.properties.minion == true
end

local function MissingStamina(token)
    return math.max(0, token.properties:MaxHitpoints() - token.properties:CurrentHitpoints())
end

local function StaminaFraction(token)
    return token.properties:CurrentHitpoints() / math.max(1, token.properties:MaxHitpoints())
end

local function CurrentMalice()
    return CharacterResource.GetMalice() or 0
end

local function MonsterLevel(token)
    return tonumber(token.properties:try_get("cr")) or 1
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

local function StrikeReach(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability:try_get("categorization") == "Signature Ability" then
            if ability.meleeAndRanged then
                return ability.rangedVariation:GetRange(token.properties)
            end
            return ability:GetRange(token.properties)
        end
    end
    return 1
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

local function WantsDrain(token)
    return CurrentMalice() >= deathScytheDrainCost
        and MissingStamina(token) >= deathScytheDrainMinimumMissing
end

--Death Scythe is melee or ranged: planning with the ranged version keeps the
--cultist at a distance, and casting the full ability still picks melee if adjacent.
MonsterAI:RegisterMove{
    id = "Human Death Cultist: Death Scythe",
    category = "Main Actions",
    monsters = deathCultistMonster,
    abilities = {"Death Scythe"},
    description = "Signature strike from range, spending 2 Malice to drain Stamina when the cultist is hurt.",
    score = function(self, ai, token, ability)
        local planning = ability.meleeAndRanged and ability.rangedVariation or ability
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, planning, DefaultTargetScore)
        if loc == nil then
            return nil, "no enemy reachable with Death Scythe"
        end
        return {score = 1.0 + math.min(0.1, targetScore*0.05), loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local planning = ability.meleeAndRanged and ability.rangedVariation or ability
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = ai:FindValidTargetsOfStrike(token, planning, scoringInfo.loc)
        table.sort(targets, function(a, b)
            return DefaultTargetScore(a.token, a.edges) > DefaultTargetScore(b.token, b.edges)
        end)
        local mode = 1
        if WantsDrain(token) then
            mode = deathScytheDrainMode
            ai:Speech(token, speechLines.drainingScythe)
        end
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause, symbols = {mode = mode}})
    end,
}

--The cultist fights at range, so these generic melee maneuvers are off for it;
--the Monster AI panel can turn them back on.
for _,moveid in ipairs({"Knockback", "Grab", "Aid Attack"}) do
    MonsterAI:SetMoveEnabledForMonster("Human Death Cultist", moveid, false)
end

MonsterAI:RegisterMove{
    id = "Human Death Cultist: Hold Range",
    category = "Maneuvers",
    monsters = deathCultistMonster,
    abilities = {},
    maxScore = 0.01,
    description = "Stay put once there is nothing left to do while an enemy is within ranged strike distance, instead of advancing into melee.",
    score = function(self, ai, token)
        local reach = StrikeReach(token)
        local pierceWalls = token.properties:GetPierceWalls()
        for _,enemy in ipairs(ai.enemyTokens or {}) do
            if LiveCreature(enemy) and MonsterAI.TargetDistance(token, enemy) <= reach
                and token:GetLineOfSight(enemy, pierceWalls) > 0 then
                return {score = 0.01}
            end
        end
        return nil, "no enemy in range from here; advancing is fine"
    end,
    execute = function(self, ai, token, scoringInfo)
    end,
}

--Rise only raises creatures that died this encounter (its first step drops the
--rest), so the AI skips them too instead of paying Malice to raise nobody.
local function DiedThisEncounter(corpse)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden or corpse.objectInstance == nil then
        return false
    end
    local component = corpse.objectInstance:GetComponent("Corpse")
    local deadToken = component ~= nil and component.properties:DeadCreatureToken() or nil
    if deadToken == nil then
        return false
    end
    local initiativeid = InitiativeQueue.GetInitiativeId(deadToken)
    return initiativeid ~= nil and q.entries[initiativeid] ~= nil
end

local function EligibleCorpses()
    local result = {}
    for _,corpse in ipairs(dmhub.allObjectTokens) do
        if corpse.valid and corpse.isCorpse and DiedThisEncounter(corpse) then
            result[#result+1] = corpse
        end
    end
    return result
end

--The ability's target filter checks line of effect, so it runs from each
--planned square rather than once in EligibleCorpses.
local function RaisableCorpses(ai, token, ability, loc, eligible)
    local result = {}
    ai:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        for _,corpse in ipairs(eligible) do
            local distance = token:Distance(corpse)
            if distance <= riseMyMinionsRange and ability:TargetPassesFilter(token, corpse, {}) then
                result[#result+1] = {token = corpse, distance = distance}
            end
        end
    end)
    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result
end

MonsterAI:RegisterMove{
    id = "Human Death Cultist: Rise, My Minions",
    category = "Maneuvers",
    monsters = deathCultistMonster,
    abilities = {"Rise, My Minions"},
    description = "Raise at least two dead minions within 5 squares, paying 1 Malice for each.",
    score = function(self, ai, token, ability)
        local malice = CurrentMalice()
        if malice < 2 then
            return nil, "not enough Malice to raise two minions"
        end
        local eligible = EligibleCorpses()
        if #eligible < 2 then
            return nil, "fewer than two corpses from this encounter"
        end
        local best = nil
        for _,info in pairs(ai.paths or {}) do
            local count = math.min(malice, #RaisableCorpses(ai, token, ability, info.loc, eligible))
            local value = count - (info.cost or 0)*0.001
            if count >= 2 and (best == nil or value > best.value) then
                best = {loc = info.loc, count = count, value = value}
            end
        end
        if best == nil then
            return nil, "fewer than two dead minions within reach"
        end
        return {score = 0.9 + math.min(0.2, (best.count - 2)*0.05), loc = best.loc, count = best.count}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local corpses = RaisableCorpses(ai, token, ability, token.loc, EligibleCorpses())
        local targets = {}
        for i=1,math.min(#corpses, CurrentMalice()) do
            local corpse = corpses[i].token
            --ExecuteAbility silently drops non-combatant targets and an empty cast still
            --runs its other behaviors, so refuse the whole cast rather than misspend.
            if not MonsterAI.TokenIsLiveCombatant(corpse) then
                ai:LogDecision("ABILITY CAST REJECTED", {
                    ability = ability.name,
                    reason = "a corpse target would be dropped by ExecuteAbility",
                })
                return
            end
            targets[#targets+1] = {token = corpse}
        end
        if #targets < 2 then
            return
        end
        ai:Speech(token, speechLines.riseMyMinions)
        --Without an area, ExecuteAbility trims the target list to the ability's single target.
        local area = dmhub.CalculateShape{
            shape = "RadiusFromCreature",
            token = token,
            radius = riseMyMinionsRange,
            checklos = false,
        }
        ai:ExecuteAbility(token, ability, targets, {
            sleep = abilityPause,
            symbols = {targetArea = area},
            targetArea = area,
        })
    end,
}

--Heals the most hurt non-minion ally (usually the cultist), or no one if nobody is hurt.
MonsterAI:RegisterPrompt{
    id = "Human Death Acolyte: Regain Stamina",
    prompts = {"Human Death Acolyte:Regain Stamina"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties)
        local best = nil
        for _,ally in ipairs(dmhub.allTokens) do
            if LiveCreature(ally) and not IsHostile(casterToken, ally) and not IsMinion(ally)
                and MonsterAI.TargetDistance(casterToken, ally) <= range
                and abilityClone:TargetPassesFilter(casterToken, ally, symbols or {}) then
                local missing = MissingStamina(ally)
                if missing > 0 and (best == nil or missing > best.missing) then
                    best = {token = ally, missing = missing}
                end
            end
        end
        if best == nil then
            return {targets = {}}
        end
        return {targets = {{token = best.token}}}
    end,
}

local function BuildCubeArea(token, ability, center)
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(center),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        checklos = false,
        altitude = center.altitude * dmhub.unitsPerSquare,
    }
end

local function TokensInArea(casterToken, ability, area)
    local result = {}
    local symbols = {targetArea = area}
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if target.valid and ability:TargetPassesFilter(casterToken, target, symbols) then
            result[#result+1] = {token = target}
        end
    end
    return result
end

local function ExecuteMapAbility(ai, token, ability, keep)
    local area = dmhub.CalculateShape{shape = "map", token = token}
    local targets = {}
    for _,targetInfo in ipairs(TokensInArea(token, ability, area)) do
        if keep == nil or keep(targetInfo.token) then
            targets[#targets+1] = targetInfo
        end
    end
    if #targets > 0 then
        ai:ExecuteAbility(token, DeepCopy(ability), targets, {
            sleep = abilityPause,
            symbols = {targetArea = area},
            targetArea = area,
        })
    end
end

local function CountHostile(casterToken, targets)
    local result = 0
    for _,targetInfo in ipairs(targets) do
        if LiveCreature(targetInfo.token) and IsHostile(casterToken, targetInfo.token) then
            result = result + 1
        end
    end
    return result
end

--HasLineOfEffect, not GetLineOfSight: it also applies the Dazzled range limit, as player targeting does.
local function FindBestCubePlan(token, ability, enemies)
    local best = nil
    local checked = {}
    for _,enemy in ipairs(enemies) do
        if LiveCreature(enemy) and token:Distance(enemy) <= ability:GetRange(token.properties)
            and not checked[enemy.loc.str]
            and RuleUtils.HasLineOfEffect(token, enemy, ability) then
            checked[enemy.loc.str] = true
            local area = BuildCubeArea(token, ability, enemy.loc)
            local count = CountHostile(token, TokensInArea(token, ability, area))
            if best == nil or count > best.count then
                best = {center = enemy.loc, count = count}
            end
        end
    end
    return best
end

local function SavingManeuverToRaise(ai, actor)
    if actor.properties.monster_type ~= "Human Death Cultist" then
        return false
    end
    local rise = FindAbility(actor, "Rise, My Minions")
    return rise ~= nil and CurrentMalice() >= 2
        and #RaisableCorpses(ai, actor, rise, actor.loc, EligibleCorpses()) >= 2
end

MonsterAI:RegisterMaliceAbility{
    id = "Human Malice: Alchemical Device",
    monsterGroups = humanGroup,
    abilities = {"Alchemical Device"},
    description = "Spend 3 Malice to throw an alchemical device at a cube catching at least two enemies.",
    score = function(self, ai, token, ability, context)
        local best = nil
        for _,actor in ipairs(context.actingTokens or {}) do
            local actorAbility = IsHuman(actor) and not IsMinion(actor) and FindMaliceAbility(actor, "Alchemical Device") or nil
            if actorAbility ~= nil and actorAbility:CanAfford(actor) and not SavingManeuverToRaise(ai, actor) then
                local plan = FindBestCubePlan(actor, actorAbility, context.enemyTokens or {})
                if plan ~= nil and plan.count >= 2 and (best == nil or plan.count > best.count) then
                    best = {actor = actor, center = plan.center, count = plan.count}
                end
            end
        end
        if best == nil then
            return nil, "no cube catches two enemies"
        end
        return {
            score = math.min(0.9, 0.7 + (best.count - 2)*0.06),
            actor = best.actor,
            center = best.center,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local actor = scoringInfo.actor
        if not LiveCreature(actor) then
            return
        end
        local actorAbility = FindMaliceAbility(actor, "Alchemical Device") or ability
        ai:RunWithTokenControl(actor, function()
            local area = BuildCubeArea(actor, actorAbility, scoringInfo.center)
            local targets = TokensInArea(actor, actorAbility, area)
            ai:ExecuteAbility(actor, DeepCopy(actorAbility), targets, {
                sleep = abilityPause,
                symbols = {targetArea = area},
                targetArea = area,
            })
        end)
    end,
}

--inflictedConditions is keyed by id (# is always 0), and ongoing effects can carry a condition too.
local function HasAnyCondition(token)
    if next(token.properties:try_get("inflictedConditions", {})) ~= nil then
        return true
    end
    local effectsTable = dmhub.GetTable("characterOngoingEffects") or {}
    for _,effect in ipairs(token.properties:ActiveOngoingEffects()) do
        local info = effectsTable[effect.ongoingEffectid]
        if info ~= nil and info.condition ~= "none" then
            return true
        end
    end
    return false
end

MonsterAI:RegisterMaliceAbility{
    id = "Human Malice: Exploit Opening",
    monsterGroups = humanGroup,
    abilities = {"Exploit Opening"},
    description = "Spend 5 Malice to give the acting humans an edge when their combined strikes make it worth it (minions count for a quarter).",
    score = function(self, ai, token, ability, context)
        local enemies = context.enemyTokens or {}
        --Minions count a quarter: 1-3 damage gains little from an edge, so one squad of four never qualifies.
        local strikingPower = 0
        for _,actor in ipairs(context.actingTokens or {}) do
            if IsHuman(actor) then
                local nearest = NearestDistance(actor, enemies)
                local speed = actor.properties:CurrentMovementSpeed() or 0
                if nearest ~= nil and nearest <= speed + StrikeReach(actor) then
                    strikingPower = strikingPower + cond(IsMinion(actor), 0.25, 1)
                end
            end
        end
        if strikingPower < 2 then
            return nil, "too little striking power acting this turn"
        end
        local conditioned = 0
        for _,enemy in ipairs(enemies) do
            if LiveCreature(enemy) and HasAnyCondition(enemy) then
                conditioned = conditioned + 1
            end
        end
        return {score = math.min(0.88, 0.7 + (strikingPower - 2)*0.05 + math.min(2, conditioned)*0.04)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        --The book buffs only the humans acting this turn.
        local acting = {}
        for _,actor in ipairs(context.actingTokens or {}) do
            acting[actor.charid] = true
        end
        ExecuteMapAbility(ai, token, ability, function(target)
            return acting[target.charid] == true
        end)
    end,
}

--allyTokens, not dmhub.allTokens: the book heals only humans in the encounter.
local function StayingPowerHumans(context)
    local result = {}
    for _,other in ipairs(context.allyTokens or {}) do
        if IsHuman(other) and not IsMinion(other) then
            result[#result+1] = other
        end
    end
    return result
end

MonsterAI:RegisterMaliceAbility{
    id = "Human Malice: Staying Power",
    monsterGroups = humanGroup,
    abilities = {"Staying Power"},
    description = "Spend 7 Malice to heal the non-minion humans when one is at half Stamina or below and it heals at least 10.",
    score = function(self, ai, token, ability, context)
        local healing = 0
        local badlyHurt = false
        for _,other in ipairs(StayingPowerHumans(context)) do
            healing = healing + math.min(MissingStamina(other), 5*MonsterLevel(other))
            if StaminaFraction(other) <= 0.5 then
                badlyHurt = true
            end
        end
        if not badlyHurt or healing < 10 then
            return nil, "no human is hurt enough to use the healing"
        end
        return {score = math.min(0.9, 0.68 + healing*0.008)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local inEncounter = {}
        for _,human in ipairs(StayingPowerHumans(context)) do
            inEncounter[human.charid] = true
        end
        ExecuteMapAbility(ai, token, ability, function(target)
            return inEncounter[target.charid] == true
        end)
    end,
}

--------------------------------------------------------------------------------
-- Human Blackguard: a leader with a two-handed sword whose signature is a
-- 1 burst. Its villain actions are cast for real and their prompts are answered
-- from the plan made when the action was scored.
--------------------------------------------------------------------------------

local blackguardMonster = {"Human Blackguard"}
local swingName = "Zweihander Swing"

--You! then the swing outranks the swing alone, so the mark lands first.
local markAndSwingBonus = 0.2

--Standard abilities behind Zweihander Swing's "one ally can make a free strike".
--Its Malice mode (an ally uses their signature) is never chosen by the AI.
local freeStrikeStandardAbilities = {["Make Free Strike"] = true, ["Free Strike"] = true}

--I Can Throw My Blade: each ally this close to the cube makes one free strike.
local throwBladeAllyRange = 5

--Villain action plans by blackguard charid, held only while the cast runs so
--its prompts follow the choices made when the action was scored.
local advancePlans = {}
local throwBladePlans = {}

local function StandardAbilityName(id)
    local ability = (dmhub.GetTable("standardAbilities") or {})[id]
    return ability ~= nil and ability.name or nil
end

--The AI's enemy list (creatures in the encounter) when it has one; a prompt
--answered outside the blackguard's own action has none, so use the whole map.
local function EnemiesOf(ai, token)
    local enemies = ai:try_get("enemyTokens")
    if enemies ~= nil then
        return enemies
    end
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and IsHostile(token, other) then
            result[#result+1] = other
        end
    end
    return result
end

--The enemies Zweihander Swing catches with the blackguard standing on loc,
--and how much the AI wants to hit them.
local function SwingTargetsAt(ai, token, swing, loc, enemies)
    local range = swing:GetRange(token.properties)
    local symbols = {mode = 1}
    local targets = {}
    local value = 0
    ai:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        for _,enemy in ipairs(enemies) do
            if LiveCreature(enemy) and MonsterAI.TargetDistance(enemy, token) <= range
                and swing:TargetPassesFilter(token, enemy, symbols) then
                targets[#targets+1] = {token = enemy}
                value = value + DefaultTargetScore(enemy)
            end
        end
    end)
    return targets, value
end

--The reachable square whose burst catches the most enemies this turn.
local function FindBestSwingSquare(ai, token, swing)
    local enemies = EnemiesOf(ai, token)
    local best = nil
    for _,info in pairs(ai.paths or {}) do
        local targets, value = SwingTargetsAt(ai, token, swing, info.loc, enemies)
        local rank = value - (info.cost or 0)*0.0001
        if #targets > 0 and (best == nil or rank > best.rank) then
            best = {loc = info.loc, targets = targets, rank = rank}
        end
    end
    return best
end

local function SwingScore(plan)
    return 1.0 + math.min(0.5, (#plan.targets - 1)*0.15)
end

local function SwingHere(ai, token, swing)
    --A trap or reaction can stop the move short; a swing at no one wastes the action.
    if #SwingTargetsAt(ai, token, swing, token.loc, EnemiesOf(ai, token)) == 0 then
        return
    end
    ai:ExecuteAbility(token, swing, nil, {sleep = abilityPause, symbols = {mode = 1}})
end

--AI-run allies other than the blackguard that could reach target this round.
local function AlliesThatCanReach(ai, token, target)
    local count = 0
    for _,ally in ipairs(ai:try_get("allyTokens") or {}) do
        if ally.charid ~= token.charid and LiveCreature(ally) and not ally.playerControlled
            and MonsterAI.TargetDistance(ally, target) <= (ally.properties:CurrentMovementSpeed() or 0) + 1 then
            count = count + 1
        end
    end
    return count
end

--Who You! should mark from loc. The mark gives the blackguard and its allies an
--edge against the target, so it only pays on an enemy someone is about to
--attack: one in swingTargets, or one an ally can reach. Minions come last.
local function ChooseMarkTarget(ai, token, you, loc, swingTargets)
    local inSwing = {}
    for _,targetInfo in ipairs(swingTargets or {}) do
        inSwing[targetInfo.token.charid] = true
    end
    local best = nil
    for _,targetInfo in ipairs(ai:FindValidTargetsOfStrike(token, you, loc)) do
        local target = targetInfo.token
        local allies = AlliesThatCanReach(ai, token, target)
        if LiveCreature(target) and (inSwing[target.charid] or allies > 0) then
            local value = DefaultTargetScore(target) + cond(inSwing[target.charid], 1, 0)
                + allies*0.3 - cond(IsMinion(target), 0.8, 0)
            if best == nil or value > best.value then
                best = {token = target, value = value}
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Human Blackguard: Zweihander Swing",
    category = "Main Actions",
    monsters = blackguardMonster,
    abilities = {swingName},
    description = "Move to the square where the burst catches the most enemies, then swing.",
    score = function(self, ai, token, swing)
        local plan = FindBestSwingSquare(ai, token, swing)
        if plan == nil then
            return nil, "no reachable square puts an enemy in the burst"
        end
        return {score = SwingScore(plan), loc = plan.loc}
    end,
    execute = function(self, ai, token, scoringInfo, swing)
        MoveCinematically(ai, token, scoringInfo.loc)
        SwingHere(ai, token, swing)
    end,
}

MonsterAI:RegisterMove{
    id = "Human Blackguard: You! and Zweihander Swing",
    category = "Main Actions",
    monsters = blackguardMonster,
    abilities = {"You!", swingName},
    description = "Mark an enemy the swing will hit (or an ally can reach), then swing with the edge.",
    score = function(self, ai, token, you, swing)
        local plan = FindBestSwingSquare(ai, token, swing)
        if plan == nil then
            return nil, "no reachable square puts an enemy in the burst"
        end
        if ChooseMarkTarget(ai, token, you, plan.loc, plan.targets) == nil then
            return nil, "no enemy worth marking from the swing square"
        end
        return {score = SwingScore(plan) + markAndSwingBonus, loc = plan.loc}
    end,
    execute = function(self, ai, token, scoringInfo, you, swing)
        MoveCinematically(ai, token, scoringInfo.loc)
        local swingTargets = SwingTargetsAt(ai, token, swing, token.loc, EnemiesOf(ai, token))
        local mark = ChooseMarkTarget(ai, token, you, token.loc, swingTargets)
        if mark ~= nil then
            ai:ExecuteAbility(token, you, {{token = mark.token}}, {sleep = abilityPause})
        end
        SwingHere(ai, token, swing)
    end,
}

MonsterAI:RegisterMove{
    id = "Human Blackguard: You!",
    category = "Maneuvers",
    monsters = blackguardMonster,
    abilities = {"You!"},
    description = "Mark an enemy an ally can reach when there is no swing to set up.",
    score = function(self, ai, token, you)
        if ChooseMarkTarget(ai, token, you, token.loc, nil) == nil then
            return nil, "no enemy in range that an ally can reach"
        end
        return {score = 0.5}
    end,
    execute = function(self, ai, token, scoringInfo, you)
        local mark = ChooseMarkTarget(ai, token, you, token.loc, nil)
        if mark ~= nil then
            ai:ExecuteAbility(token, you, {{token = mark.token}}, {sleep = abilityPause})
        end
    end,
}

--A creature's free strikes as a grant makes them: outside its action economy,
--never a charge. planning is a copy for target search, which treats anything
--named "Melee Free Strike" as able to charge.
local function GrantedFreeStrikes(ally)
    local result = {}
    for _,ability in ipairs(ally.properties:GetActivatedAbilities()) do
        if ability.categorization == "Basic Attack" then
            local variants = {ability}
            if ability.meleeAndRanged then
                variants = {ability.meleeVariation, ability.rangedVariation}
            end
            for _,variant in ipairs(variants) do
                local strike = DeepCopy(variant)
                strike.actionResourceId = "none"
                strike.disableSquadCoordination = true
                if strike.keywords ~= nil then
                    strike.keywords.Charge = nil
                end
                result[#result+1] = strike
            end
        end
    end
    return result
end

--The free strike ally would make right now against one of candidates (every
--enemy when nil), picking the target the AI would rather hit.
local function BestGrantedFreeStrike(ai, ally, candidates)
    candidates = candidates or EnemiesOf(ai, ally)
    local pierceWalls = ally.properties:GetPierceWalls()
    local best = nil
    for _,strike in ipairs(GrantedFreeStrikes(ally)) do
        local range = strike:GetRange(ally.properties)
        for _,enemy in ipairs(candidates) do
            if LiveCreature(enemy) and IsHostile(ally, enemy)
                and not enemy.properties:HasNamedCondition("Hidden")
                and MonsterAI.TargetDistance(strike:GetRangeSource(ally), enemy) <= range
                and strike:TargetPassesFilter(ally, enemy, {})
                and ally:GetLineOfSight(enemy, pierceWalls) > 0 then
                --a full monster hits harder than a minion, so it goes first.
                local value = DefaultTargetScore(enemy) + cond(IsMinion(ally), 0, 0.5)
                if best == nil or value > best.value then
                    best = {ally = ally, strike = strike, target = enemy, value = value}
                end
            end
        end
    end
    return best
end

--Makes a granted free strike directly. The grant's own prompt chain would hand
--the ally's choice to the Director, so the handlers below decline the grant
--after making the strike themselves.
local function MakeGrantedFreeStrike(ai, plan)
    --RunWithTokenControl clears the expected prompt; keep the outer action's.
    local expected = ai:try_get("_tmp_expectedPromptTarget")
    local ok, err = ai:RunWithTokenControl(plan.ally, function()
        ai:ExecuteAbility(plan.ally, plan.strike, {{token = plan.target}}, {sleep = 0.5})
    end)
    ai._tmp_expectedPromptTarget = expected
    if not ok then
        ai:LogDecision("PROMPT ERROR", {
            ability = plan.strike.name,
            reason = "granted free strike failed: " .. tostring(err),
        })
    end
end

local function GrantsFreeStrike(ability)
    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        if behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior"
            and behavior:try_get("abilityType") == "standard"
            and freeStrikeStandardAbilities[StandardAbilityName(behavior:try_get("standardAbility", ""))] then
            return true
        end
    end
    return false
end

--Zweihander Swing: "One ally within 10 squares can make a free strike."
MonsterAI:RegisterPrompt{
    id = "Human Blackguard: Swing Ally Free Strike",
    prompts = {"Human Blackguard:Invoked Ability"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if not GrantsFreeStrike(abilityClone) then
            return nil
        end
        local origin = abilityClone:GetRangeSource(casterToken)
        local range = abilityClone:GetRange(casterToken.properties)
        local pierceWalls = casterToken.properties:GetPierceWalls()
        local best = nil
        for _,ally in ipairs(dmhub.allTokens) do
            if LiveCreature(ally) and not ally.playerControlled and ally.charid ~= casterToken.charid
                and not IsHostile(casterToken, ally)
                and MonsterAI.TargetDistance(origin, ally) <= range
                and abilityClone:TargetPassesFilter(casterToken, ally, symbols or {})
                and origin:GetLineOfSight(ally, pierceWalls) > 0 then
                local plan = BestGrantedFreeStrike(ai, ally, nil)
                if plan ~= nil and (best == nil or plan.value > best.value) then
                    best = plan
                end
            end
        end
        if best ~= nil then
            MakeGrantedFreeStrike(ai, best)
        end
        return {targets = {}}
    end,
}

--Advance! comes in two builds: "shift {Movement Speed}" then two swings, or
--shift, swing, shift, swing, shift. Only the second lets the blackguard swing
--from two different squares.
local function CanShiftBetweenSwings(ability)
    local swings = 0
    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        if behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" then
            local abilityType = behavior:try_get("abilityType", "custom")
            if abilityType == "named"
                and string.lower(behavior:try_get("namedAbility", "")) == string.lower(swingName) then
                swings = swings + 1
            elseif abilityType == "standard" and swings == 1
                and StandardAbilityName(behavior:try_get("standardAbility", "")) == "Shift" then
                return true
            end
        end
    end
    return false
end

--Advance!'s second swing at an enemy the first already hit is worth less: its
--slow is already on, and it may be down. At or below advanceLikelyDownStamina
--(a tier 2 swing) a creature probably falls to the first swing.
local advanceRepeatValue = 0.8
local advanceRepeatValueIfLikelyDown = 0.2
local advanceLikelyDownStamina = 6

local function SecondSwingValue(first, second)
    local hitFirst = {}
    for _,targetInfo in ipairs(first.targets) do
        hitFirst[targetInfo.token.charid] = true
    end
    local value = 0
    for _,targetInfo in ipairs(second.targets) do
        local target = targetInfo.token
        local worth = DefaultTargetScore(target)
        if hitFirst[target.charid] then
            if IsMinion(target) or target.properties:CurrentHitpoints() <= advanceLikelyDownStamina then
                worth = worth*advanceRepeatValueIfLikelyDown
            else
                worth = worth*advanceRepeatValue
            end
        end
        value = value + worth
    end
    return value
end

--Where Advance! shifts to before the first swing (first) and before the second
--(second), catching the most enemies over both swings. With no enemy in reach
--it just closes in. nil when there is no enemy at all.
local function PlanAdvance(ai, token, ability, swing)
    local speed = token.properties:CurrentMovementSpeed() or 0
    local enemies = EnemiesOf(ai, token)
    local squares = {}
    local haveStart = false
    for _,info in pairs(ai:CalculateMovementPaths(token, speed*10, {"shift"})) do
        squares[#squares+1] = {loc = info.loc, cost = (info.cost or 0)/10}
        haveStart = haveStart or info.loc.str == token.loc.str
    end
    if not haveStart then
        squares[#squares+1] = {loc = token.loc, cost = 0}
    end

    local hitting = {}
    for _,square in ipairs(squares) do
        local targets, value = SwingTargetsAt(ai, token, swing, square.loc, enemies)
        square.targets = targets
        square.hits = #targets
        square.value = value
        if square.hits > 0 then
            hitting[#hitting+1] = square
        end
    end

    local split = CanShiftBetweenSwings(ability)
    local best = nil
    for _,first in ipairs(hitting) do
        for _,second in ipairs(split and hitting or {first}) do
            local moved = first.cost + first.loc:DistanceInTiles(second.loc)
            if moved <= speed then
                local rank = first.value + SecondSwingValue(first, second) - moved*0.001
                if best == nil or rank > best.rank then
                    best = {first = first.loc, second = second.loc, hits = first.hits + second.hits, rank = rank}
                end
            end
        end
    end
    if best ~= nil then
        return best
    end

    for _,square in ipairs(squares) do
        local distance = nil
        ai:ExecuteWithTheoreticalMovementLoc(token, square.loc, function()
            distance = NearestDistance(token, enemies)
        end)
        if distance ~= nil then
            local rank = -distance - square.cost*0.001
            if best == nil or rank > best.rank then
                best = {first = square.loc, second = square.loc, hits = 0, rank = rank}
            end
        end
    end
    return best
end

--Fallback when a planned shift square is out of reach: the best swing square
--this shift can reach (the current square when nothing beats it).
local function BestReachableSwingSquare(ai, token, range)
    local swing = FindAbility(token, swingName)
    if swing == nil then
        return nil
    end
    local enemies = EnemiesOf(ai, token)
    local best = nil
    for _,info in pairs(ai:CalculateMovementPaths(token, range*10, {"shift"})) do
        local _, value = SwingTargetsAt(ai, token, swing, info.loc, enemies)
        local rank = value - (info.cost or 0)*0.0001
        if best == nil or rank > best.rank then
            best = {loc = info.loc, rank = rank}
        end
    end
    return best ~= nil and best.loc or nil
end

--Advance!'s shifts: to plan.first before the first swing and plan.second
--between the swings. Any other shift (the one after both swings) is declined.
MonsterAI:RegisterPrompt{
    id = "Human Blackguard: Advance! Shift",
    prompts = {"Human Blackguard:Shift"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = advancePlans[invokerToken.charid]
        if plan == nil then
            --not Advance!: the generic Shift handler answers.
            return nil
        end
        local phase = plan.swings
        local loc = nil
        if phase <= 1 and not plan.shifted[phase] then
            plan.shifted[phase] = true
            loc = cond(phase == 0, plan.first, plan.second)
        end
        if loc == nil or loc.str == casterToken.loc.str then
            return {targets = {}}
        end

        local range = abilityClone:GetRange(casterToken.properties)
        local reachable = false
        for _,info in pairs(ai:CalculateMovementPaths(casterToken, range*10, {"shift"})) do
            if info.loc.str == loc.str then
                reachable = true
                break
            end
        end
        if not reachable then
            loc = BestReachableSwingSquare(ai, casterToken, range)
            if loc == nil or loc.str == casterToken.loc.str then
                return {targets = {}}
            end
        end

        casterToken:MarkMovementArrow(loc, {straightline = false, ignorecreatures = false})
        MonsterAI.Sleep(movementPause)
        casterToken:ClearMovementArrow()
        return {targets = {{loc = loc}}}
    end,
}

--A swing an ability invokes (Advance!) asks for its targets: every enemy in the
--burst, in mode 1 (the free strike grant).
MonsterAI:RegisterPrompt{
    id = "Human Blackguard: Invoked Zweihander Swing",
    prompts = {"Human Blackguard:" .. swingName},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = advancePlans[invokerToken.charid]
        if plan ~= nil then
            plan.swings = plan.swings + 1
        end
        if symbols ~= nil then
            symbols.mode = 1
        end
        local targets = SwingTargetsAt(ai, casterToken, abilityClone, casterToken.loc, EnemiesOf(ai, casterToken))
        return {targets = targets}
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Human Blackguard: Advance!",
    monsters = blackguardMonster,
    abilities = {"Advance!"},
    description = "Shift up to speed and swing twice, splitting the shift between two spots when that catches more enemies.",
    score = function(self, ai, token, ability, context)
        local swing = FindAbility(token, swingName)
        if swing == nil then
            return nil, "no Zweihander Swing to use"
        end
        local plan = PlanAdvance(ai, token, ability, swing)
        if plan == nil then
            return nil, "no enemy to advance on"
        end
        if plan.hits == 0 then
            --nobody in reach: only worth it as a free advance in the round's last window.
            plan.score = 0.1
        else
            plan.score = math.min(0.95, 0.45 + plan.hits*0.12)
        end
        plan.reason = string.format("swing at %s then %s; %d hits",
            MonsterAI.LocLogName(plan.first), MonsterAI.LocLogName(plan.second), plan.hits)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        advancePlans[token.charid] = {
            first = scoringInfo.first,
            second = scoringInfo.second,
            swings = 0,
            shifted = {},
        }
        local ok, err = ai:RunYieldingFunction(function()
            ai:ExecuteAbility(token, ability, {{token = token}}, {sleep = abilityPause})
        end)
        advancePlans[token.charid] = nil
        if not ok then
            error(err, 0)
        end
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Human Blackguard: Back!",
    monsters = blackguardMonster,
    abilities = {"Back!"},
    description = "Slide every enemy within 5 squares, best when the blackguard is crowded.",
    score = function(self, ai, token, ability, context)
        local range = ability:GetRange(token.properties)
        local caught = 0
        local adjacent = 0
        for _,enemy in ipairs(EnemiesOf(ai, token)) do
            local distance = MonsterAI.TargetDistance(enemy, token)
            if LiveCreature(enemy) and distance <= range and ability:TargetPassesFilter(token, enemy, {mode = 1}) then
                caught = caught + 1
                if distance <= 1 then
                    adjacent = adjacent + 1
                end
            end
        end
        if caught == 0 then
            return nil, "no enemy within the burst"
        end
        return {score = math.min(0.95, 0.35 + caught*0.12 + adjacent*0.08), enemies = caught}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

local function DistanceToArea(token, area)
    local result = nil
    for _,loc in ipairs(area.locations or {}) do
        local distance = token:Distance(loc)
        if result == nil or distance < result then
            result = distance
        end
    end
    return result
end

MonsterAI:RegisterVillainAction{
    id = "Human Blackguard: I Can Throw My Blade and So Should You!",
    monsters = blackguardMonster,
    abilities = {"I Can Throw My Blade and So Should You!"},
    description = "Throw the swing at the cube catching the most enemies; nearby allies each free strike one of them.",
    score = function(self, ai, token, ability, context)
        local plan = FindBestCubePlan(token, ability, EnemiesOf(ai, token))
        if plan == nil or plan.count == 0 then
            return nil, "no cube in range catches an enemy"
        end
        return {score = math.min(0.95, 0.4 + plan.count*0.15), center = plan.center, enemies = plan.count}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildCubeArea(token, ability, scoringInfo.center)
        local targets = TokensInArea(token, ability, area)
        throwBladePlans[token.charid] = {area = area, used = {}}
        local ok, err = ai:RunYieldingFunction(function()
            ai:ExecuteAbility(token, DeepCopy(ability), targets, {
                sleep = abilityPause,
                symbols = {targetArea = area},
                targetArea = area,
            })
        end)
        throwBladePlans[token.charid] = nil
        if not ok then
            error(err, 0)
        end
    end,
}

--I Can Throw My Blade's newer build asks each ally near the cube for a free
--strike against one of its targets; the generic Free Strike handler answers.
--The older build asks, for each enemy struck (the prompt's caster), which
--allies free strike it. Each ally near the cube strikes once.
MonsterAI:RegisterPrompt{
    id = "Human Blackguard: Throw My Blade Ally Free Strikes",
    prompts = {"Human Blackguard:Ally Makes Free Strike Against Specific Target"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = throwBladePlans[invokerToken.charid]
        local victim = casterToken
        if plan == nil or not LiveCreature(victim) or not IsHostile(invokerToken, victim) then
            return {targets = {}}
        end
        local best = nil
        for _,ally in ipairs(dmhub.allTokens) do
            if LiveCreature(ally) and not ally.playerControlled and ally.charid ~= invokerToken.charid
                and not plan.used[ally.charid] and not IsHostile(invokerToken, ally)
                and (DistanceToArea(ally, plan.area) or math.huge) <= throwBladeAllyRange then
                local strike = BestGrantedFreeStrike(ai, ally, {victim})
                if strike ~= nil and (best == nil or strike.value > best.value) then
                    best = strike
                end
            end
        end
        if best ~= nil then
            plan.used[best.ally.charid] = true
            MakeGrantedFreeStrike(ai, best)
        end
        return {targets = {}}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Human Blackguard: Parry!",
    monsters = blackguardMonster,
    triggers = {"Parry!"},
    description = "Halve the damage of a strike against the blackguard or an adjacent ally.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}
