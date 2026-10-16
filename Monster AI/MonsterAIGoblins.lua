local mod = dmhub.GetModLoading()

MonsterAI:RegisterTactic{
    id = "Goblin Sniper: Hold Position",
    monsters = {"Goblin Sniper"},
    description = "Snipers shoot without moving whenever possible, spreading fire among targets reachable from their current positions.",
    score = function(self, token, tokenLoc, enemy, ability)
        if token.properties:try_get("monster_type", "") ~= "Goblin Sniper"
            or ability.name ~= "Bow" then
            return
        end

        -- Target evaluation temporarily relocates the token. The zero-cost
        -- squad path still identifies its actual position before that probe.
        for _,member in ipairs(self.squadMembers) do
            if member.token.charid == token.charid then
                for _,path in pairs(member.paths or {}) do
                    if path.cost == 0 and path.loc.str == tokenLoc.str then
                        -- Outweigh movement bonuses and the 10000 repeat-target
                        -- penalty; stationary targets still use normal squad rules.
                        return 100000
                    end
                end
                return
            end
        end
    end,
}

--------------------------------------------------------------------------------
-- Start-of-turn Goblin Malice abilities.
--------------------------------------------------------------------------------

local maliceAbilityPause = 0.9
local speechPause = 0.45
local goblinModeEffectId = "5646898c-0c0e-4973-823e-13172eaaaba2"
local goblinModeSpeedBonus = 2

-- Tiny Stabs is worth 5 Malice from this many stabs, and a must-do from the
-- upper count on.
local tinyStabsMinimumStabs = 3
local tinyStabsMustDoStabs = 5

-- The caster shouts one of these as the Malice ability goes off.
local goblinMaliceSpeech = {
    ["Swamp Stink"] = {
        "Smell that? That's winning!",
        "Hold your breath, tall-folk!",
    },
    ["Goblin Mode"] = {
        "GOBLIN MODE!",
        "Faster, you lot!",
    },
}

local function Speak(ai, token, abilityName)
    local lines = goblinMaliceSpeech[abilityName]
    if lines ~= nil then
        ai:Speech(token, lines)
        ai.Sleep(speechPause)
    end
end

-- Swamp Stink is used at most once per encounter. Keyed by initiative queue
-- guid; local memory only, so like the framework's own Malice history it
-- forgets on a Lua reload and does not see casts the Director made by hand.
local g_swampStinkUsedByEncounter = {}

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject
        and token.properties ~= nil and not token.properties:IsDead()
end

local function HasOngoingEffect(token, effectid)
    local effects = nil
    pcall(function()
        effects = token.properties:ActiveOngoingEffects(true)
    end)
    for _,effect in ipairs(effects or {}) do
        if effect.ongoingEffectid == effectid then
            return true
        end
    end
    return false
end

local function HasAuraFromAbility(abilityid)
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.properties ~= nil then
            for _,aura in ipairs(token.properties:try_get("auras", {})) do
                if aura:try_get("sourceAbilityId") == abilityid then
                    return true
                end
            end
        end
    end
    return false
end

local function HasGoblinKeyword(token)
    local keywords = nil
    pcall(function()
        keywords = token.properties:Keywords()
    end)
    if type(keywords) ~= "table" then
        return false
    end
    for name,value in pairs(keywords) do
        if value and string.lower(tostring(name)) == "goblin" then
            return true
        end
    end
    return false
end

-- Casts a targetType "map" group ability. With no target list it hits every
-- creature the ability's filter accepts; pass targetTokens to narrow that.
local function ExecuteMapAbility(ai, caster, ability, targetTokens)
    local area = dmhub.CalculateShape{
        shape = "map",
        token = caster,
    }
    local symbols = {targetArea = area}
    local targets = {}
    if targetTokens ~= nil then
        for _,target in ipairs(targetTokens) do
            if LiveCreature(target) then
                targets[#targets+1] = {token = target}
            end
        end
    else
        for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
            if target.valid and ability:TargetPassesFilter(caster, target, symbols) then
                targets[#targets+1] = {token = target}
            end
        end
    end

    ai:ExecuteAbility(caster, DeepCopy(ability), targets, {
        sleep = maliceAbilityPause,
        symbols = symbols,
        targetArea = area,
    })
end

-- The strikes this creature could use on its turn, each with its range and the
-- enemies it may legally target.
local function StrikeOptions(ai, actor)
    local result = {}
    for _,ability in ipairs(actor.properties:GetActivatedAbilities()) do
        if ability:HasKeyword("Strike") and ability.categorization ~= "Triggered Action"
            and ability.categorization ~= "Malice" and ability:CanAfford(actor) then
            local enemies = {}
            for _,enemy in ipairs(ai.enemyTokens) do
                if LiveCreature(enemy) and ability:TargetPassesFilter(actor, enemy, {}) then
                    enemies[#enemies+1] = enemy
                end
            end
            if #enemies > 0 then
                result[#result+1] = {
                    range = ability:GetRange(actor.properties),
                    enemies = enemies,
                }
            end
        end
    end
    return result
end

-- True when a location in paths (other than those in skip) lets one of the
-- strikes reach an enemy it can see. Charges are just movement plus a strike,
-- so ordinary pathing already covers them.
local function CanStrikeFromPaths(ai, actor, strikes, paths, skip)
    local pierceWalls = actor.properties:GetPierceWalls()
    for key,info in pairs(paths) do
        if skip == nil or skip[key] == nil then
            local found = false
            ai:ExecuteWithTheoreticalMovementLoc(actor, info.loc, function()
                for _,strike in ipairs(strikes) do
                    for _,enemy in ipairs(strike.enemies) do
                        if MonsterAI.TargetDistance(actor, enemy) <= strike.range
                            and actor:GetLineOfSight(enemy, pierceWalls) > 0 then
                            found = true
                            return
                        end
                    end
                end
            end)
            if found then
                return true
            end
        end
    end
    return false
end

-- True when this acting creature cannot strike an enemy this turn with its
-- current speed but could with Goblin Mode's +2.
local function NeedsGoblinModeToReach(ai, goblinMode, caster, actor)
    local mover = ai:GetMovementToken(actor)
    if not LiveCreature(mover) or not goblinMode:TargetPassesFilter(caster, mover, {})
        or HasOngoingEffect(mover, goblinModeEffectId) then
        return false
    end

    local speed = mover.properties:CurrentMovementSpeed() or 0
    if speed <= 0 then
        return false
    end

    local strikes = StrikeOptions(ai, actor)
    if #strikes == 0 then
        return false
    end

    local basePaths = ai:CalculateMovementPaths(actor, speed*10)
    if CanStrikeFromPaths(ai, actor, strikes, basePaths) then
        return false
    end

    local boostedPaths = ai:CalculateMovementPaths(actor, (speed + goblinModeSpeedBonus)*10)
    return CanStrikeFromPaths(ai, actor, strikes, boostedPaths, basePaths)
end

MonsterAI:RegisterMaliceAbility{
    id = "Goblin Malice: Swamp Stink",
    monsterGroups = {"Goblin"},
    abilities = {"Swamp Stink"},
    description = "Spend 7 Malice on Swamp Stink the first time the goblins can afford it in an encounter.",
    score = function(self, ai, token, ability, context)
        local queue = context.initiativeQueue
        if queue ~= nil and g_swampStinkUsedByEncounter[queue.guid] then
            return nil, "Swamp Stink was already used this encounter"
        end
        if HasAuraFromAbility(ability:try_get("guid")) then
            return nil, "Swamp Stink mist is already on the map"
        end

        local enemies = 0
        for _,enemy in ipairs(context.enemyTokens or {}) do
            if LiveCreature(enemy) and ability:TargetPassesFilter(token, enemy, {}) then
                enemies = enemies + 1
            end
        end
        if enemies == 0 then
            return nil, "no non-goblin enemies to affect"
        end

        -- Only one Malice ability is used per turn. This outranks Goblin Mode,
        -- but yields to a must-do Tiny Stabs, whose adjacency may not last,
        -- while Swamp Stink can wait a turn.
        return {score = 0.98, enemies = enemies}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, "Swamp Stink")
        ExecuteMapAbility(ai, token, ability)
        local queue = context.initiativeQueue
        if queue ~= nil then
            g_swampStinkUsedByEncounter[queue.guid] = true
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Goblin Malice: Goblin Mode",
    monsterGroups = {"Goblin"},
    abilities = {"Goblin Mode"},
    description = "Spend 3 Malice on Goblin Mode when an acting goblin can only reach an enemy to strike with the +2 speed.",
    score = function(self, ai, token, ability, context)
        local needing = 0
        for _,actor in ipairs(context.actingTokens or {}) do
            if LiveCreature(actor) and NeedsGoblinModeToReach(ai, ability, token, actor) then
                needing = needing + 1
            end
        end

        if needing == 0 then
            return nil, "no acting goblin needs +2 speed to reach an enemy"
        end

        return {
            score = math.min(0.95, 0.75 + needing*0.05),
            needing = needing,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, "Goblin Mode")
        ExecuteMapAbility(ai, token, ability)
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Goblin Malice: Tiny Stabs",
    monsterGroups = {"Goblin"},
    abilities = {"Tiny Stabs"},
    description = "Spend 5 Malice on Tiny Stabs when goblins adjacent to enemies add up to at least 3 stabs; 5 or more is a must-do.",
    score = function(self, ai, token, ability, context)
        -- Each enemy takes 1 damage per goblin adjacent to it, so one goblin
        -- next to two enemies is two stabs.
        local goblins = {}
        for _,ally in ipairs(context.allyTokens or {}) do
            if LiveCreature(ally) and HasGoblinKeyword(ally) then
                goblins[#goblins+1] = ally
            end
        end

        local stabs = 0
        local targets = {}
        for _,enemy in ipairs(context.enemyTokens or {}) do
            if LiveCreature(enemy) then
                local enemyStabs = 0
                for _,goblin in ipairs(goblins) do
                    if MonsterAI.TargetDistance(goblin, enemy) <= 1 then
                        enemyStabs = enemyStabs + 1
                    end
                end
                if enemyStabs > 0 then
                    stabs = stabs + enemyStabs
                    targets[#targets+1] = enemy
                end
            end
        end

        if stabs < tinyStabsMinimumStabs then
            return nil, string.format("only %d stabs; needs %d", stabs, tinyStabsMinimumStabs)
        end

        -- 3 stabs just clears the 0.65 threshold; the must-do count scores 1.
        local steps = tinyStabsMustDoStabs - tinyStabsMinimumStabs
        local progress = math.min(1, (stabs - tinyStabsMinimumStabs)/steps)
        return {
            score = 0.7 + progress*0.3,
            stabs = stabs,
            targets = targets,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        -- Only enemies who will actually be stabbed, so the log is not full
        -- of zero-damage rolls against creatures with no goblin beside them.
        ExecuteMapAbility(ai, token, ability, scoringInfo.targets)
    end,
}

--------------------------------------------------------------------------------
-- Goblin Stinker: Swamp Gas.
--
-- The haze is difficult terrain for non-goblins and deals 2 poison per square
-- moved inside it, forced movement included. The stinker places it to trap
-- as many enemies as it can and to sit across the routes they would take to
-- reach the stinker. It scores above Toxic Winds, so it goes first and the
-- winds can then slide enemies through the haze.
--------------------------------------------------------------------------------

local swampGasCaughtValue = 4      -- per enemy standing in the haze
-- Closeness bonus: proximityValue per square the cube's centre is inside
-- proximityRange of the nearest free enemy (up to +3 at distance 0).
local swampGasProximityValue = 0.5
local swampGasProximityRange = 6
local swampGasPathSquareValue = 1  -- per haze square between an enemy and the stinker
local swampGasAllyPenalty = 2      -- per non-goblin ally caught in it
local swampGasOverlapPenalty = 1   -- per square already under another stinker's haze
local swampGasPause = 0.6
-- Candidates are first ranked on a cheap square-grid estimate; only this many
-- of the best are checked against the real cube shape and line of effect.
local swampGasCandidatesToVerify = 8

local goblinStinkerSpeech = {
    "Breathe deep, tall-folk!",
    "Smells like home!",
    "Mind your step. Heh.",
}

local function SquareKey(x, y)
    return string.format("%d,%d", x, y)
end

-- Draw Steel counts diagonal steps as 1, so distance is the larger axis gap.
local function GridDistance(ax, ay, bx, by)
    return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function OffsetLoc(loc, dx, dy)
    local result = loc
    for _=1,math.abs(dx) do
        if dx > 0 then
            result = result.east
        else
            result = result.west
        end
    end
    for _=1,math.abs(dy) do
        if dy > 0 then
            result = result.north
        else
            result = result.south
        end
    end
    return result
end

-- The haze only affects creatures without the Goblin keyword.
local function CreaturesTheHazeAffects(tokens)
    local result = {}
    for _,other in ipairs(tokens or {}) do
        if LiveCreature(other) and not HasGoblinKeyword(other) then
            result[#result+1] = other
        end
    end
    return result
end

-- Every square on some shortest route from an enemy to the stinker, not
-- counting the squares the enemy or the stinker stand on: the squares the
-- enemy could cross on its way to the stinker.
local function SquaresBetweenEnemiesAndStinker(token, enemies)
    local result = {}
    local stinkerSquares = {}
    for _,loc in ipairs(token.locsOccupying) do
        stinkerSquares[SquareKey(loc.x, loc.y)] = true
    end

    local tx, ty = token.loc.x, token.loc.y
    for _,enemy in ipairs(enemies) do
        local ownSquares = {}
        for _,loc in ipairs(enemy.locsOccupying) do
            ownSquares[SquareKey(loc.x, loc.y)] = true
        end

        local ex, ey = enemy.loc.x, enemy.loc.y
        local distance = GridDistance(ex, ey, tx, ty)
        for x=math.min(ex, tx),math.max(ex, tx) do
            for y=math.min(ey, ty),math.max(ey, ty) do
                local key = SquareKey(x, y)
                if not ownSquares[key] and not stinkerSquares[key]
                    and GridDistance(ex, ey, x, y) + GridDistance(x, y, tx, ty) == distance then
                    result[key] = true
                end
            end
        end
    end
    return result
end

-- Value of a haze over the given squares (a list of {x, y}). The square maps
-- go from SquareKey to the charid of the creature standing there; covered
-- holds squares already under another stinker's haze. A covered square earns
-- no route credit and costs the overlap penalty, so clouds spread out.
local function ScoreSwampGasSquares(squares, betweenSquares, enemySquares, allySquares, covered)
    local pathSquares = 0
    local overlap = 0
    local caught = {}
    local allies = {}
    for _,square in ipairs(squares) do
        local key = SquareKey(square.x, square.y)
        if covered[key] then
            overlap = overlap + 1
        elseif betweenSquares[key] then
            pathSquares = pathSquares + 1
        end
        if enemySquares[key] ~= nil then
            caught[enemySquares[key]] = true
        end
        if allySquares[key] ~= nil then
            allies[allySquares[key]] = true
        end
    end

    local numCaught = 0
    for _ in pairs(caught) do
        numCaught = numCaught + 1
    end
    local numAllies = 0
    for _ in pairs(allies) do
        numAllies = numAllies + 1
    end

    return {
        score = numCaught*swampGasCaughtValue + pathSquares*swampGasPathSquareValue
            - numAllies*swampGasAllyPenalty - overlap*swampGasOverlapPenalty,
        caught = numCaught,
        pathSquares = pathSquares,
        allies = numAllies,
        overlap = overlap,
    }
end

local function BuildSwampGasArea(token, ability, center)
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(center),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        checklos = false,
        altitude = center.withGroundAltitude.altitude * dmhub.unitsPerSquare,
    }
end

local function SquaresOf(tokens)
    local result = {}
    for _,other in ipairs(tokens) do
        for _,loc in ipairs(other.locsOccupying) do
            result[SquareKey(loc.x, loc.y)] = other.charid
        end
    end
    return result
end

-- Squares already under another stinker's haze. A placed haze is stored in its
-- caster's auras list with the cube it covers. The stinker's own earlier haze
-- is ignored: by the rules it has expired at the start of this turn.
local function SquaresUnderOtherSwampGas(token, ability)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if other.valid and other.properties ~= nil and other.charid ~= token.charid then
            for _,aura in ipairs(other.properties:try_get("auras", {})) do
                if aura:try_get("name") == ability.name
                    or aura:try_get("sourceAbilityId") == ability:try_get("guid") then
                    local area = aura:GetArea()
                    for _,loc in ipairs(area ~= nil and area.locations or {}) do
                        result[SquareKey(loc.x, loc.y)] = true
                    end
                end
            end
        end
    end
    return result
end

local function SwampGasProximityBonus(cx, cy, enemies)
    local nearest = nil
    for _,enemy in ipairs(enemies) do
        local d = GridDistance(cx, cy, enemy.loc.x, enemy.loc.y)
        if nearest == nil or d < nearest then
            nearest = d
        end
    end
    if nearest == nil then
        return 0
    end
    return math.max(0, swampGasProximityRange - nearest)*swampGasProximityValue
end

local function FindSwampGasPlan(ai, token, ability)
    local covered = SquaresUnderOtherSwampGas(token, ability)

    -- Enemies already in another stinker's haze are trapped; they are not
    -- worth a second cloud.
    local enemies = {}
    for _,enemy in ipairs(CreaturesTheHazeAffects(ai.enemyTokens)) do
        local inHaze = false
        for _,loc in ipairs(enemy.locsOccupying) do
            if covered[SquareKey(loc.x, loc.y)] then
                inHaze = true
            end
        end
        if not inHaze then
            enemies[#enemies+1] = enemy
        end
    end
    if #enemies == 0 then
        return nil, "no non-goblin enemies outside existing Swamp Gas"
    end
    local enemySquares = SquaresOf(enemies)
    local allySquares = SquaresOf(CreaturesTheHazeAffects(ai.allyTokens))
    local betweenSquares = SquaresBetweenEnemiesAndStinker(token, enemies)

    -- Estimate every cube centre in range on the square grid. A 3 cube
    -- reaches one square out from its centre.
    local range = ability:GetRange(token.properties)
    local reach = math.floor(ability:GetRadius(token.properties)/2)
    local ox, oy = token.loc.x, token.loc.y
    local candidates = {}
    for dx=-range,range do
        for dy=-range,range do
            local squares = {}
            for sx=-reach,reach do
                for sy=-reach,reach do
                    squares[#squares+1] = {x = ox + dx + sx, y = oy + dy + sy}
                end
            end
            local estimate = ScoreSwampGasSquares(squares, betweenSquares, enemySquares, allySquares, covered)
            estimate.proximity = SwampGasProximityBonus(ox + dx, oy + dy, enemies)
            estimate.score = estimate.score + estimate.proximity
            if estimate.score > 0 then
                estimate.dx = dx
                estimate.dy = dy
                candidates[#candidates+1] = estimate
            end
        end
    end
    if #candidates == 0 then
        return nil, "no placement traps an enemy or covers a route to the stinker enough to outweigh overlap"
    end
    table.sort(candidates, function(a, b)
        return a.score > b.score
    end)

    -- Re-score the best estimates on the real shape, which also checks the
    -- centre is on the map, in range and in line of effect.
    local pierceWalls = token.properties:GetPierceWalls()
    local best = nil
    local verified = 0
    for _,candidate in ipairs(candidates) do
        if verified >= swampGasCandidatesToVerify then
            break
        end
        local center = OffsetLoc(token.loc, candidate.dx, candidate.dy)
        if center.valid and center.isOnMap and token:Distance(center) <= range
            and token:GetLineOfSight(center, pierceWalls) > 0 then
            verified = verified + 1
            local area = BuildSwampGasArea(token, ability, center)
            local squares = {}
            for _,loc in ipairs(area.locations or {}) do
                squares[#squares+1] = {x = loc.x, y = loc.y}
            end
            local actual = ScoreSwampGasSquares(squares, betweenSquares, enemySquares, allySquares, covered)
            actual.proximity = candidate.proximity
            actual.score = actual.score + actual.proximity
            if actual.score > 0 and (best == nil or actual.score > best.score) then
                actual.center = center
                best = actual
            end
        end
    end

    if best == nil then
        return nil, "no worthwhile placement is in range and line of effect"
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Goblin Stinker: Swamp Gas",
    category = "Maneuvers",
    monsters = {"Goblin Stinker"},
    abilities = {"Swamp Gas"},
    description = "Maneuver: place the haze to catch enemies (+4 each), close to enemies (up to +3), and over squares between enemies and the stinker (+1 each). Scores above Toxic Winds so the winds can slide enemies through it.",
    score = function(self, ai, token, ability)
        return FindSwampGasPlan(ai, token, ability)
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, goblinStinkerSpeech)
        ai.Sleep(speechPause)

        local area = BuildSwampGasArea(token, ability, scoringInfo.center)
        ai:ExecuteAbility(token, DeepCopy(ability), {}, {
            sleep = swampGasPause,
            symbols = {targetArea = area},
            targetArea = area,
        })
    end,
}
