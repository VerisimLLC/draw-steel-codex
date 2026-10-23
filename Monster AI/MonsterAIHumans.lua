local mod = dmhub.GetModLoading()

--Monster AI for the Human band: the Death Cultist and its Death Acolytes, plus
--the Human group Malice features any human can call on. Other human stat
--blocks fall back to generic AI for their own abilities.

local humanGroup = {"Human"}
local deathCultistMonster = {"Human Death Cultist"}

local movementPause = 0.6
local abilityPause = 1.0

local speechLines = {
    riseMyMinions = {"Rise! Your work is not done!", "Death is no excuse!"},
    drainingScythe = {"Your life is mine!"},
}

--Death Scythe's "2 Malice: regain half the damage dealt" is its second mode.
local deathScytheDrainMode = 2
local deathScytheDrainCost = 2
--Only drain when the cultist is missing at least this much Stamina, so the
--heal (half of 6-12 damage) is not wasted.
local deathScytheDrainMinimumMissing = 5

local riseMyMinionsRange = 5

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject and token.properties ~= nil
        and not token.properties:IsDead()
end

--TokensAreFriendly is the allegiance test the AI core uses. IsFriend also
--counts any creature the Director controls, so it calls an unowned hero a friend.
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

--Group Malice features only, so a human's own ability of the same name is
--never picked up instead.
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

--How far a human strikes: its signature ability's range, else melee 1.
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

--------------------------------------------------------------------------------
-- Death Cultist: Death Scythe and Rise, My Minions.
--------------------------------------------------------------------------------

local function WantsDrain(token)
    return CurrentMalice() >= deathScytheDrainCost
        and MissingStamina(token) >= deathScytheDrainMinimumMissing
end

--The cultist is support, so it plans from the ranged variation: ranged strikes
--made next to an enemy lose an edge, which keeps it standing back. Cast through
--the full ability, which picks melee if it ends up adjacent anyway.
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

--The cultist is ranged support, but would otherwise spend its spare maneuver
--walking into melee for the generic Knockback, Grab or Aid Attack. Off by
--default for it; the Monster AI panel can still turn them back on.
for _,moveid in ipairs({"Knockback", "Grab", "Aid Attack"}) do
    MonsterAI:SetMoveEnabledForMonster("Human Death Cultist", moveid, false)
end

--Once the cultist has struck, nothing else scores and the framework's
--fallback walks it toward the nearest enemy. Holding scores just above
--nothing while an enemy is already in Death Scythe's range keeps it back.
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

--Rise, My Minions only raises creatures who died during this encounter. Its
--first step drops any corpse whose creature's initiative entry is not in the
--current combat (it died before the fight), so the AI must skip those too or it
--pays Malice and its maneuver to raise nothing.
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

--Corpse objects the cultist could raise from anywhere: dead minions (the
--ability's own target filter checks that) who died this encounter. None of
--this depends on where the cultist stands, so build it once per decision.
local function EligibleCorpses(token, ability)
    local result = {}
    for _,corpse in ipairs(dmhub.allObjectTokens) do
        if corpse.valid and corpse.isCorpse and DiedThisEncounter(corpse)
            and ability:TargetPassesFilter(token, corpse, {}) then
            result[#result+1] = corpse
        end
    end
    return result
end

--The eligible corpses within reach of a square, nearest first.
local function RaisableCorpses(ai, token, loc, eligible)
    local result = {}
    ai:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        for _,corpse in ipairs(eligible) do
            local distance = token:Distance(corpse)
            if distance <= riseMyMinionsRange then
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
        local eligible = EligibleCorpses(token, ability)
        if #eligible < 2 then
            return nil, "fewer than two dead minions to raise"
        end
        local best = nil
        for _,info in pairs(ai.paths or {}) do
            local count = math.min(malice, #RaisableCorpses(ai, token, info.loc, eligible))
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
        --Pay for no more corpses than there is Malice for (1 each).
        local corpses = RaisableCorpses(ai, token, token.loc, EligibleCorpses(token, ability))
        local targets = {}
        for i=1,math.min(#corpses, CurrentMalice()) do
            local corpse = corpses[i].token
            --ExecuteAbility silently drops targets it does not see as live
            --combatants; a cast left with no corpses would still apply its
            --other behaviors, so refuse rather than misspend.
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
        --The burst is passed as an area so ExecuteAbility keeps every corpse;
        --it trims an explicit target list to the ability's single target otherwise.
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

--------------------------------------------------------------------------------
-- Death Acolyte: Necrotic Bolt's heal.
--------------------------------------------------------------------------------

--Necrotic Bolt lets one creature within 5 regain 1 Stamina. Give it to the
--most hurt non-minion ally (usually the cultist); skip it if nobody is hurt.
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

--------------------------------------------------------------------------------
-- Human group Malice features (start of a human's turn).
--------------------------------------------------------------------------------

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

--Map-wide Malice features are cast over a map area with an explicit target
--list. keep(target) narrows the list; nil keeps everything the filter allows.
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

--The cube centred on an enemy that catches the most enemies.
local function FindBestCubePlan(token, ability, enemies)
    local best = nil
    local checked = {}
    for _,enemy in ipairs(enemies) do
        if LiveCreature(enemy) and token:Distance(enemy) <= ability:GetRange(token.properties)
            and not checked[enemy.loc.str] then
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

--A Death Cultist with minions to raise should keep its maneuver for that.
local function SavingManeuverToRaise(ai, actor)
    if actor.properties.monster_type ~= "Human Death Cultist" then
        return false
    end
    local rise = FindAbility(actor, "Rise, My Minions")
    return rise ~= nil and CurrentMalice() >= 2
        and #RaisableCorpses(ai, actor, actor.loc, EligibleCorpses(actor, rise)) >= 2
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

--A condition is either inflicted directly (inflictedConditions is keyed by
--condition id, so # is always 0) or comes from an ongoing effect that names one.
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

--Exploit Opening is worth 5 Malice when several humans act this turn with an
--enemy in reach; conditioned enemies (double edge) make it better still.
MonsterAI:RegisterMaliceAbility{
    id = "Human Malice: Exploit Opening",
    monsterGroups = humanGroup,
    abilities = {"Exploit Opening"},
    description = "Spend 5 Malice to give the acting humans an edge when their combined strikes make it worth it (minions count for a quarter).",
    score = function(self, ai, token, ability, context)
        local enemies = context.enemyTokens or {}
        --Minion strikes deal 1-3 damage, so an edge on one is worth far less
        --than on a non-minion. A lone squad of four does not qualify.
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

--Staying Power heals each non-minion human in the encounter 5 x level; only
--worth 7 Malice when someone is badly hurt and the healing would not be wasted.
--allyTokens holds only combatants, so humans elsewhere on the map are ignored.
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
