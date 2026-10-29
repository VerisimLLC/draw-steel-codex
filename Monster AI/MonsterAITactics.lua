local mod = dmhub.GetModLoading()

MonsterAI:RegisterTactic{
    id = "Flanking",
    description = "Monsters using this tactic try to move into position to flank enemies they are attacking in melee",
    score = function(self, token, tokenLoc, enemy, ability)
        local flanking = false
        for _,ally in ipairs(self.allyTokens) do
            if ally.charid ~= token.charid and MonsterAI.TargetDistance(ally, enemy) <= 1 then
                if (enemy.loc.y - tokenLoc.y) == (ally.loc.y - enemy.loc.y) and (enemy.loc.x - tokenLoc.x) == (ally.loc.x - enemy.loc.x) then
                    flanking = true
                    break
                end
            end
        end

        if flanking then
            return 1
        end
    end,
}

MonsterAI:RegisterTactic{
    id = "Aid Attack",
    description = "Monsters using this tactic prefer to attack enemies who their allies are aiding attack on.",
    score = function(self, token, tokenLoc, enemy, ability)
        if enemy.properties._tmp_ai_aidAttack == true then
            return 1
        end
    end,
}

MonsterAI:RegisterTactic{
    id = "High Ground",
    description = "Monsters using this tactic prefer to attack from higher ground.",
    score = function(self, token, tokenLoc, enemy, ability)
        local targetAltitude = game.currentFloor:GetAltitudeAtLoc(enemy.loc)
        local ourAltitude = game.currentFloor:GetAltitudeAtLoc(tokenLoc)
        if ourAltitude > targetAltitude then
            return 1
        end
    end,
}

--Zone directive "Force Into": strongly prefer striking from a square where the
--strike's push, pull or slide could move the target into a Force Into zone.
--This is a planning estimate (straight distances, no walls or creatures); the
--Push!/Pull!/Slide! prompt checks the real path when the movement happens.
local forceIntoEdges = 3

--{kind = "push"|"pull"|"slide", distance = n} for the forced movement a
--strike's tier 2 result does (tier 3 when tier 2 has none), or false.
local g_abilityForcedMovement = setmetatable({}, {__mode = "k"})

local function AbilityForcedMovement(ability)
    local cached = g_abilityForcedMovement[ability]
    if cached ~= nil then
        return cached
    end
    ---@type {kind: string, distance: number}|false
    local result = false
    for _,behavior in ipairs(ability:try_get("behaviors") or {}) do
        local tiers = behavior:try_get("tiers")
        if type(tiers) == "table" then
            for _,tierIndex in ipairs({2, 3}) do
                local text = type(tiers[tierIndex]) == "string" and string.lower(tiers[tierIndex]) or ""
                --vertical movement goes up and down, not across the map.
                if not string.find(text, "vertical", 1, true) then
                    for _,kind in ipairs({"push", "pull", "slide"}) do
                        local distance = string.match(text, kind .. " +(%d+)")
                        if distance ~= nil then
                            --%d+ always converts; the "or 0" only satisfies the type checker.
                            result = {kind = kind, distance = tonumber(distance) or 0}
                            break
                        end
                    end
                end
                if result then
                    break
                end
            end
        end
        if result then
            break
        end
    end
    g_abilityForcedMovement[ability] = result
    return result
end

--Squares within distance of the enemy that would put it in a zone the
--attacker has a Force Into directive for, memoised for the planning frame.
local function ForceIntoSquaresNear(ai, attacker, enemy, distance)
    local memo = ai:PlanningMemo()
    memo.forceIntoSquares = memo.forceIntoSquares or {}
    local key = attacker.charid .. "|" .. enemy.charid .. "|" .. enemy.loc.str .. "|" .. distance
    local squares = memo.forceIntoSquares[key]
    if squares == nil then
        squares = {}
        for dx = -distance,distance do
            for dy = -distance,distance do
                local loc = enemy.loc:dir(dx, dy)
                if (dx ~= 0 or dy ~= 0) and MonsterAI.InDirectiveZone("forceInto", enemy, loc, attacker) then
                    squares[#squares+1] = loc
                end
            end
        end
        memo.forceIntoSquares[key] = squares
    end
    return squares
end

MonsterAI:RegisterTactic{
    id = "Force Into Zones",
    description = "Monsters using this tactic strongly prefer to attack from where the strike's push, pull or slide can move the target into a zone whose type has the Force Into Monster AI directive.",
    score = function(self, token, tokenLoc, enemy, ability)
        if not MonsterAI.AnyDirectiveZones("forceInto", token) or token:IsFriend(enemy) then
            return nil
        end
        local forced = AbilityForcedMovement(ability)
        if not forced or MonsterAI.InDirectiveZone("forceInto", enemy, nil, token) then
            return nil
        end
        local distance = forced.distance - enemy.properties:Stability()
            + token.properties:ForcedMovementBonus(forced.kind)
        if distance <= 0 then
            return nil
        end
        --a push moves the target straight away from the attacker and a pull
        --straight toward it, a square of distance per square moved.
        local fromTarget = tokenLoc:DistanceInTiles(enemy.loc)
        for _,square in ipairs(ForceIntoSquaresNear(self, token, enemy, distance)) do
            local moved = square:DistanceInTiles(enemy.loc)
            local fromSquare = tokenLoc:DistanceInTiles(square)
            local reachable
            if forced.kind == "push" then
                local gained = fromSquare - fromTarget
                reachable = gained >= moved and gained <= distance
            elseif forced.kind == "pull" then
                local closed = fromTarget - fromSquare
                reachable = fromSquare >= 1 and closed >= moved and closed <= distance
            else
                reachable = true
            end
            if reachable then
                return forceIntoEdges
            end
        end
    end,
}

--Behavior modules (MonsterAI:RegisterBehavior in MonsterAI.lua) ---------------
--Each is off unless its `monsters` list names the monster type, or an
--Encounter of the Week script switches it ("Monster AI: Bully on for Goblin
--Sniper"; see the eotw skill's script reference).

--Bully: prefers the enemies with the smallest share of their Stamina left.
--A target at full Stamina gets nothing; one at 0 or below (dying) gets
--bullyMaxEdges. It also cancels TargetStaminaBias, the usual slight lean
--toward healthy targets, so only weakness counts. An edge is worth 0.1 of
--a target's score, so 6 edges make a dying hero worth 1.6 targets.
MonsterAI.bullyMaxEdges = 6

MonsterAI:RegisterBehavior{
    id = "Bully",
    aliases = {"Bullies", "Bullying"},
    description = "Prefers to attack the enemies with the smallest share of their Stamina left, more strongly the closer they are to 0.",
    monsters = {},
    targetEdges = function(self, token, tokenLoc, enemy, ability)
        if enemy.isObject or enemy.properties == nil or token:IsFriend(enemy) then
            return nil
        end
        local maxStamina = enemy.properties:MaxHitpoints()
        if maxStamina <= 0 then
            return nil
        end
        local share = math.max(0, math.min(1, enemy.properties:CurrentHitpoints()/maxStamina))
        return MonsterAI.bullyMaxEdges*(1 - share) - MonsterAI.TargetStaminaBias(enemy)/0.1
    end,
}

--Avoid Opportunity Attacks: the work is in MonsterAI.lua (OpportunityAttackers,
--ChooseAvoidingOpportunityAttacks); the size of the penalty is
--MonsterAI.opportunityAttackPenalty. On for every monster; turn it off per type
--in the Monster AI panel, with SetMoveEnabledForMonster, or in an EotW script.
MonsterAI:RegisterBehavior{
    id = MonsterAI.avoidOpportunityAttacksBehavior,
    aliases = {"Avoids Opportunity Attacks", "Avoid OAs", "Avoids OAs"},
    description = "Will not walk away from an adjacent enemy who could make an opportunity attack, unless the plan that does is worth far more than any that does not.",
    allMonsters = true,
}
