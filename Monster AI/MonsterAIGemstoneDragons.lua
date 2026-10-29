local mod = dmhub.GetModLoading()

--Monster AI for the gemstone dragons (Solo Gemstone Dragons draft): Topaz,
--Emerald, Ruby, Amethyst and Sapphire. They share the psionic field chassis,
--so the planners near the top serve all of them.

local topazMonster = {"Topaz Dragon"}
local topazGroup = {"Topaz Dragon"}

local movementPause = 0.6
local abilityPause = 1.0

local TRIGGERED_ACTION = "b9bc06dd-80f1-4f33-bc55-25c114e3300c"
local SPIKE_KEYWORD = "topazspike"
local PYRO_WAVE_COST = 10

--Candidate speech lines, kept together so they are easy to revise after playtesting.
local speech = {
    pyroWave = {"Burn, little sparks!", "Feel the fire under your feet!"},
    heatDeath = {"Your warmth is mine.", "Be still. Be cold."},
    topazFlare = {"My field burns!", "Closer, and be consumed!"},
    absoluteZero = {"Nothing moves at absolute zero.", "I take your heat and give you nothing."},
    siphon = {"The earth answers me.", "Topaz, rise!"},
}

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject and token.properties ~= nil
        and not token.properties:IsDead()
end

local function EnemyTokens(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and not other:IsFriend(token) then
            result[#result+1] = other
        end
    end
    return result
end

local function PsychicImmune(target)
    if target == nil or target.properties == nil then
        return false
    end
    local ok, value = pcall(function()
        return ExecuteGoblinScript('Immunities("Psychic")', target.properties:LookupSymbol{}, 0, "Topaz AI")
    end)
    return ok and (tonumber(value) or 0) > 0
end

--The psionic field's size, the same formula the monster's field aura uses: base 3,
--grown by the dragon's Villain Action 2 effect, shrunk by Field Diminished stacks.
local g_fieldFormulas = {
    ["Topaz Dragon"] = '3 + 2 * Stacks("Topaz Flare") - Stacks("Topaz Field Diminished")',
    ["Emerald Dragon"] = '3 + 3 * Stacks("Emerald Flower") - Stacks("Emerald Field Diminished")',
    ["Ruby Dragon"] = '3 + 3 * Stacks("Ruby Bloom") - Stacks("Ruby Field Diminished")',
    ["Amethyst Dragon"] = '3 + 3 * Stacks("Amethyst Flash") - Stacks("Amethyst Field Diminished")',
    ["Sapphire Dragon"] = '3 + 3 * Stacks("Star Sapphire") - Stacks("Sapphire Field Diminished")',
}

local function FieldSize(token)
    local formula = g_fieldFormulas[token.properties:try_get("monster_type") or ""] or "PsionicFieldSize"
    local value = ExecuteGoblinScript(formula, token.properties:LookupSymbol{}, 0, "Gemstone AI")
    return math.max(0, tonumber(value) or 0)
end

local function Malice()
    return tonumber(CharacterResource.GetMalice()) or 0
end

local function MoveCinematically(ai, token, loc)
    if loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc) then
        ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(movementPause)
    end
end

local function TokensInArea(casterToken, ability, area)
    local result = {}
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if target.valid and not target.isObject and ability:TargetPassesFilter(casterToken, target, {targetArea = area}) then
            result[#result+1] = {token = target}
        end
    end
    return result
end

local function CountByAllegiance(casterToken, targets)
    local enemies, allies, slowed = 0, 0, 0
    for _,info in ipairs(targets) do
        local target = info.token
        if LiveCreature(target) and target.charid ~= casterToken.charid then
            if target:IsFriend(casterToken) then
                allies = allies + 1
            else
                enemies = enemies + 1
                if target.properties:HasNamedCondition("Slowed") then
                    slowed = slowed + 1
                end
            end
        end
    end
    return enemies, allies, slowed
end

--radius overrides the ability's own, for abilities whose size depends on a mode.
local function BuildCubeArea(token, ability, anchor, radius)
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(anchor),
        token = token,
        range = ability:GetRange(token.properties),
        radius = radius or ability:GetRadius(token.properties),
        checklos = false,
        altitude = anchor.altitude * dmhub.unitsPerSquare,
    }
end

local function BuildLineArea(token, ability, originLoc, targetLoc)
    return dmhub.CalculateShape{
        shape = "line",
        targetPoint = token:PosAtLoc(targetLoc),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        locOverride = originLoc,
        checklos = true,
        altitude = originLoc.altitude * dmhub.unitsPerSquare,
    }
end

--Best cube for an area ability: anchors on and around each enemy in range,
--scored by enemies caught minus allies caught. extraScore(area, targets) can
--add ability-specific value.
local function FindBestCubePlan(token, ability, extraScore, radiusOverride)
    local range = ability:GetRange(token.properties)
    local radius = math.max(1, tonumber(radiusOverride or ability:GetRadius(token.properties)) or 1)
    local best = nil
    local checked = {}
    for _,enemy in ipairs(EnemyTokens(token)) do
        for dx = 1 - radius, 0 do
            for dy = 1 - radius, 0 do
                local anchor = enemy.loc:dir(dx, dy)
                local key = string.format("%d,%d", anchor.x, anchor.y)
                if not checked[key] and token:Distance(anchor) <= range then
                    checked[key] = true
                    local area = BuildCubeArea(token, ability, anchor, radius)
                    local targets = TokensInArea(token, ability, area)
                    local enemies, allies = CountByAllegiance(token, targets)
                    local value = enemies - allies*2
                    if extraScore ~= nil then
                        value = value + extraScore(area, targets)
                    end
                    if enemies > 0 and (best == nil or value > best.value) then
                        best = {anchor = anchor, enemies = enemies, allies = allies, value = value}
                    end
                end
            end
        end
    end
    return best
end

local function ExecuteAreaAbility(ai, token, ability, area, targets, options)
    options = options or {}
    local symbols = options.symbols or {}
    --a fresh table per cast: the cast keeps and mutates its symbols.
    symbols = table.shallow_copy(symbols)
    symbols.targetArea = area
    ai:ExecuteAbility(token, ability, targets, {
        sleep = abilityPause,
        symbols = symbols,
        targetArea = area,
    })
end

--Line plans from every square the dragon can still reach: lines are "within 1",
--so their origin is wherever the dragon stands when it breathes.
local function FindBestLinePlan(ai, token, ability, slowedBonus)
    local length = ability:GetRange(token.properties)
    local enemies = EnemyTokens(token)
    local candidates = {}
    for _,info in pairs(ai.paths or {}) do
        for _,enemy in ipairs(enemies) do
            if info.loc:DistanceInTiles(enemy.loc) <= length + 2 then
                candidates[#candidates+1] = {targetLoc = enemy.loc, locOverride = info.loc, cost = info.cost or 0}
            end
        end
    end
    if #candidates == 0 then
        for _,enemy in ipairs(enemies) do
            candidates[#candidates+1] = {targetLoc = enemy.loc, locOverride = token.loc, cost = 0}
        end
    end

    local plan = ai:FindBestLinePlan(token, ability, {
        candidates = candidates,
        logPlan = false,
        scorefn = function(target, candidate)
            if not LiveCreature(target) or target.charid == token.charid then
                return 0
            end
            if target:IsFriend(token) then
                return -2
            end
            local value = 1
            if slowedBonus ~= nil and target.properties:HasNamedCondition("Slowed") then
                value = value + slowedBonus
            end
            return value - (candidate.cost or 0)*0.0001
        end,
    })
    if plan == nil then
        return nil
    end
    local numEnemies, allies, slowed = CountByAllegiance(token, plan.targets)
    if numEnemies == 0 then
        return nil
    end
    return {
        loc = plan.locOverride or token.loc,
        targetLoc = plan.targetLoc,
        enemies = numEnemies,
        allies = allies,
        slowed = slowed,
        value = plan.score,
    }
end

local function ExecuteLinePlan(ai, token, ability, plan)
    MoveCinematically(ai, token, plan.loc)
    local area = BuildLineArea(token, ability, token.loc, plan.targetLoc)
    local targets = TokensInArea(token, ability, area)
    ExecuteAreaAbility(ai, token, ability, area, targets)
end

--------------------------------------------------------------------------------
-- Main actions.
--------------------------------------------------------------------------------

local function RaysIgnisTargetScore(target, edges)
    if target.isObject then
        return 0.05
    end
    local value = 1 + (edges or 0)*0.1 + MonsterAI.TargetStaminaBias(target)
    if PsychicImmune(target) then
        value = value + 0.2
    end
    return value
end

MonsterAI:RegisterMove{
    id = "Topaz Dragon: Rays Ignis",
    category = "Main Actions",
    monsters = topazMonster,
    abilities = {"Rays Ignis"},
    description = "Fire burning rays at two enemies, preferring those with a psychic immunity (the rays have an edge against them).",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, RaysIgnisTargetScore)
        if loc ~= nil then
            return {score = 1.1 + math.min(0.15, (targetScore or 0)*0.03), loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        table.sort(targets, function(a, b)
            return RaysIgnisTargetScore(a.token, a.edges) > RaysIgnisTargetScore(b.token, b.edges)
        end)
        table.resize_array(targets, ability:GetNumTargets(token))
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Topaz Dragon: Rays Frigidus",
    category = "Main Actions",
    monsters = topazMonster,
    abilities = {"Rays Frigidus"},
    description = "Freeze a line of enemies, especially ones already slowed (they become restrained); preferred over Rays Ignis once it catches two or more.",
    score = function(self, ai, token, ability)
        local plan = FindBestLinePlan(ai, token, ability, 0.5)
        if plan == nil or plan.allies > 0 then
            return nil, "no line catches enemies without allies"
        end
        if plan.enemies < 2 and plan.slowed == 0 then
            return nil, "a single unslowed enemy is better served by Rays Ignis"
        end
        plan.score = 0.75 + 0.15*math.min(4, plan.enemies) + 0.2*math.min(2, plan.slowed)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteLinePlan(ai, token, ability, scoringInfo)
    end,
}

MonsterAI:RegisterMove{
    id = "Topaz Dragon: Pyro Wave",
    category = "Main Actions",
    monsters = topazMonster,
    abilities = {"Pyro Wave"},
    description = "Spend 10 Malice on Pyro Wave when its 10 x 4 line catches three or more enemies (two when Malice is plentiful).",
    score = function(self, ai, token, ability)
        local plan = FindBestLinePlan(ai, token, ability, nil)
        if plan == nil or plan.allies > 0 then
            return nil, "no line catches enemies without allies"
        end
        local needed = cond(Malice() >= PYRO_WAVE_COST + 5, 2, 3)
        if plan.enemies < needed then
            return nil, string.format("only %d enemies in the best line", plan.enemies)
        end
        plan.score = 1.7 + 0.1*math.min(4, plan.enemies - needed)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ai:Speech(token, speech.pyroWave)
        ai.Sleep(0.4)
        local area = BuildLineArea(token, ability, token.loc, scoringInfo.targetLoc)
        local targets = TokensInArea(token, ability, area)
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

--------------------------------------------------------------------------------
-- Topaz Siphon: three spikes. The first cube is the ability's own target; the
-- second and third arrive as prompts, answered from the plan stored here.
--------------------------------------------------------------------------------

--charid -> list of {anchor} still to place this cast.
local g_pendingSpikes = {}

local function ExistingCrystals(keyword)
    return Encounter.GetTargetableObjectsWithKeyword(keyword)
end

local function ExistingSpikes()
    return ExistingCrystals(SPIKE_KEYWORD)
end

local function SquaresOf(area)
    local result = {}
    for _,loc in ipairs(area.locations or {}) do
        result[#result+1] = loc
    end
    return result
end

local function ChebyshevToSquares(loc, squares)
    local best = 999
    for _,sq in ipairs(squares) do
        best = math.min(best, math.max(math.abs(loc.x - sq.x), math.abs(loc.y - sq.y)))
    end
    return best
end

--Up to `count` non-overlapping cubes for conjured crystals (Topaz spikes, Emerald
--pillars). A cube is worth its occupants (each takes the eruption) plus every
--enemy it newly brings within `influence` of a crystal with this keyword (the
--crystal's pulse reaches them). Allies and the dragon's own squares are avoided.
local function PlanCrystals(token, ability, keyword, count, influence)
    local range = ability:GetRange(token.properties)
    local radius = math.max(1, tonumber(ability:GetRadius(token.properties)) or 1)
    local enemies = EnemyTokens(token)
    if #enemies == 0 then
        return nil
    end

    local blocked = {}
    for _,loc in ipairs(token:LocsOccupyingWhenAt(token.loc) or {}) do
        blocked[string.format("%d,%d", loc.x, loc.y)] = true
    end

    local covered = {}
    for _,enemy in ipairs(enemies) do
        if ExecuteGoblinScript(string.format('DistanceToObjectWithKeyword("%s")', keyword), enemy.properties:LookupSymbol{}, 999, "Gemstone AI") <= influence then
            covered[enemy.charid] = true
        end
    end
    --existing crystal footprints, as squares, so new cubes do not overlap them.
    for _,crystal in ipairs(ExistingCrystals(keyword)) do
        for dx = -1, 1 do
            for dy = -1, 1 do
                local l = crystal.loc:dir(dx, dy)
                blocked[string.format("%d,%d", l.x, l.y)] = true
            end
        end
    end

    local candidates = {}
    local seen = {}
    for _,enemy in ipairs(enemies) do
        for dx = -radius, radius - 1 do
            for dy = -radius, radius - 1 do
                local anchor = enemy.loc:dir(dx, dy)
                local key = string.format("%d,%d", anchor.x, anchor.y)
                if not seen[key] and token:Distance(anchor) <= range then
                    seen[key] = true
                    local area = BuildCubeArea(token, ability, anchor)
                    local squares = SquaresOf(area)
                    local ok = #squares > 0
                    for _,sq in ipairs(squares) do
                        if blocked[string.format("%d,%d", sq.x, sq.y)] or not sq.isOnMap then
                            ok = false
                        end
                    end
                    if ok then
                        local _, allies = CountByAllegiance(token, TokensInArea(token, ability, area))
                        if allies == 0 then
                            candidates[#candidates+1] = {anchor = anchor, area = area, squares = squares}
                        end
                    end
                end
            end
        end
    end

    local chosen = {}
    local total = 0
    for pick = 1, count do
        local best, bestValue = nil, nil
        for _,c in ipairs(candidates) do
            local overlaps = false
            for _,other in ipairs(chosen) do
                if ChebyshevToSquares(c.anchor, other.squares) <= 1 then
                    overlaps = true
                end
            end
            if not overlaps then
                local value = 0
                for _,enemy in ipairs(enemies) do
                    local distance = ChebyshevToSquares(enemy.loc, c.squares)
                    if distance == 0 then
                        value = value + 1
                    end
                    if distance <= influence and not covered[enemy.charid] then
                        value = value + 0.6
                    end
                end
                if bestValue == nil or value > bestValue then
                    best, bestValue = c, value
                end
            end
        end
        if best == nil then
            break
        end
        chosen[#chosen+1] = best
        total = total + bestValue
        for _,enemy in ipairs(enemies) do
            if ChebyshevToSquares(enemy.loc, best.squares) <= influence then
                covered[enemy.charid] = true
            end
        end
    end

    if #chosen == 0 then
        return nil
    end
    return {spikes = chosen, value = total}
end

local function PlanSiphon(token, ability)
    return PlanCrystals(token, ability, SPIKE_KEYWORD, 3, 2)
end

--Casts a multi-cube ability: the first cube is the ability's own target, the
--rest arrive as prompts that RegisterCubeFollowUps answers from g_pendingSpikes.
local function ExecuteMultiCube(ai, token, ability, anchors, radius, options)
    local pending = {}
    for i = 2, #anchors do
        pending[#pending+1] = anchors[i]
    end
    g_pendingSpikes[token.charid] = pending
    local area = BuildCubeArea(token, ability, anchors[1], radius)
    ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area), options)
    g_pendingSpikes[token.charid] = nil
end

--Answers the prompt for a follow-up cube. The parent's targetArea is passed down
--to its invokes, so the answer must carry the new cube as targetArea, not just a
--location. fallback(casterToken, abilityClone) plans a cube when there is no plan
--(the Director cast the ability while the AI runs).
local function RegisterCubeFollowUps(promptName, fallback)
    MonsterAI:RegisterPrompt{
        prompts = {promptName},
        handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
            local pending = g_pendingSpikes[casterToken.charid]
            local anchor = nil
            if pending ~= nil and #pending > 0 then
                anchor = table.remove(pending, 1)
            else
                anchor = fallback(casterToken, abilityClone)
            end
            if anchor == nil then
                return nil
            end
            local area = BuildCubeArea(casterToken, abilityClone, anchor)
            symbols.targetArea = area
            return {targets = TokensInArea(casterToken, abilityClone, area), targetArea = area}
        end,
    }
end

MonsterAI:RegisterMove{
    id = "Topaz Dragon: Topaz Siphon",
    category = "Maneuvers",
    monsters = topazMonster,
    abilities = {"Topaz Siphon"},
    description = "Raise three topaz spikes on and around enemies so the round-start pulse drains them for Malice; stops adding spikes once the board is saturated.",
    score = function(self, ai, token, ability)
        if #ExistingSpikes() >= 6 then
            return nil, "six or more spikes already stand"
        end
        local plan = PlanSiphon(token, ability)
        if plan == nil or plan.value < 1 then
            return nil, "no spike placement reaches an enemy"
        end
        plan.score = 0.75 + 0.05*math.min(4, plan.value)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local anchors = {}
        for _,spike in ipairs(scoringInfo.spikes) do
            anchors[#anchors+1] = spike.anchor
        end
        ai:Speech(token, speech.siphon)
        ai.Sleep(0.3)
        ExecuteMultiCube(ai, token, ability, anchors)
    end,
}

RegisterCubeFollowUps("Topaz Dragon:Topaz Siphon", function(casterToken, abilityClone)
    local plan = PlanSiphon(casterToken, abilityClone)
    return plan ~= nil and plan.spikes[1].anchor or nil
end)

--------------------------------------------------------------------------------
-- Start-of-turn Malice features.
--------------------------------------------------------------------------------

--Malice the dragon keeps back for Pyro Wave when three or more enemies are
--close enough to line up this turn.
local function MaliceReserve(token)
    local malice = Malice()
    if malice < PYRO_WAVE_COST then
        return 0
    end
    local near = 0
    for _,enemy in ipairs(EnemyTokens(token)) do
        if token:Distance(enemy) <= 11 then
            near = near + 1
        end
    end
    return cond(near >= 3, PYRO_WAVE_COST, 0)
end

local function CanSpareMalice(token, cost)
    return Malice() - cost >= MaliceReserve(token)
end

MonsterAI:RegisterMaliceAbility{
    id = "Topaz Dragon Malice: Solo Action",
    monsterGroups = topazGroup,
    abilities = {"Solo Action"},
    description = "Spend 5 Malice for an extra main action while enemies remain, unless it would leave too little for Pyro Wave.",
    score = function(self, ai, token, ability, context)
        if #context.enemyTokens == 0 then
            return nil, "no enemies"
        end
        if not CanSpareMalice(token, 5) then
            return nil, "keeping Malice for Pyro Wave"
        end
        return {score = 0.78}
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Topaz Dragon Malice: Thermal Exchange",
    monsterGroups = topazGroup,
    abilities = {"Thermal Exchange"},
    description = "Sap a 3 cube holding two or more enemies: they are slowed (P<2) in difficult terrain, and it explodes next turn.",
    score = function(self, ai, token, ability, context)
        if not CanSpareMalice(token, 5) then
            return nil, "keeping Malice for Pyro Wave"
        end
        local plan = FindBestCubePlan(token, ability, function(area, targets)
            local slowable = 0
            for _,info in ipairs(targets) do
                local t = info.token
                if LiveCreature(t) and not t:IsFriend(token)
                    and t.properties:AttributeForPotencyResistance("prs") < 2 then
                    slowable = slowable + 1
                end
            end
            return slowable*0.3
        end)
        if plan == nil or plan.allies > 0 or plan.enemies < 2 then
            return nil, "no 3 cube holds two or more enemies without allies"
        end
        return {score = math.min(0.9, 0.62 + 0.06*plan.enemies), anchor = plan.anchor}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildCubeArea(token, ability, scoringInfo.anchor)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area))
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Topaz Dragon Malice: Psi Boost",
    monsterGroups = topazGroup,
    abilities = {"Psi Boost"},
    description = "Spend 3 Malice to empower the next psionic ability: +2 damage per target when enemies are clustered, otherwise a double edge.",
    minimumScore = 0.65,
    score = function(self, ai, token, ability, context)
        if #context.enemyTokens == 0 then
            return nil, "no enemies"
        end
        if not CanSpareMalice(token, 3) then
            return nil, "keeping Malice for Pyro Wave"
        end
        --boosts only help an ability the dragon can use this turn.
        local inReach = 0
        for _,enemy in ipairs(context.enemyTokens) do
            if token:Distance(enemy) <= 5 + token.properties:CurrentMovementSpeed() then
                inReach = inReach + 1
            end
        end
        if inReach == 0 then
            return nil, "no enemy within reach of a psionic ability this turn"
        end
        local mode = cond(inReach >= 3, 2, 1)
        return {score = 0.67, mode = mode}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:ExecuteAbility(token, ability, nil, {sleep = 0.5, symbols = {mode = scoringInfo.mode}})
    end,
}

--------------------------------------------------------------------------------
-- Villain actions.
--------------------------------------------------------------------------------

MonsterAI:RegisterVillainAction{
    id = "Topaz Dragon: Heat Death",
    monsters = topazMonster,
    abilities = {"Heat Death"},
    description = "Drain the heat from the 4 cube holding the most enemies, especially flying ones.",
    score = function(self, ai, token, ability, context)
        local plan = FindBestCubePlan(token, ability, function(area, targets)
            local midair = 0
            for _,info in ipairs(targets) do
                if not info.token:IsFriend(token) and (tonumber(ExecuteGoblinScript("FloorAltitude", info.token.properties:LookupSymbol{}, 0, "Topaz AI")) or 0) > 0 then
                    midair = midair + 1
                end
            end
            return midair*0.5
        end)
        if plan == nil then
            return nil
        end
        return {score = math.min(1, 0.4 + 0.15*plan.value), anchor = plan.anchor}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.heatDeath)
        ai.Sleep(0.4)
        local area = BuildCubeArea(token, ability, scoringInfo.anchor)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area))
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Topaz Dragon: Topaz Flare",
    monsters = topazMonster,
    abilities = {"Topaz Flare"},
    description = "Expand the field to a 5 aura that explodes each round, sooner when enemies already crowd within 5.",
    score = function(self, ai, token, ability, context)
        local near = 0
        for _,enemy in ipairs(EnemyTokens(token)) do
            if token:Distance(enemy) <= 5 then
                near = near + 1
            end
        end
        return {score = math.min(1, 0.45 + 0.12*near)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.topazFlare)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Topaz Dragon: Absolute Zero",
    monsters = topazMonster,
    abilities = {"Absolute Zero"},
    description = "Encase itself in 50 temporary Stamina, more urgently the more Stamina it has lost.",
    score = function(self, ai, token, ability, context)
        local p = token.properties
        local lost = 1 - p:CurrentHitpoints()/math.max(1, p:MaxHitpoints())
        return {score = math.min(1, 0.35 + lost)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.absoluteZero)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Triggered actions.
--------------------------------------------------------------------------------

local function TriggeredActionAvailable(token)
    local p = token.properties
    local available = (p:GetResources()[TRIGGERED_ACTION] or 0) - p:GetResourceUsage(TRIGGERED_ACTION, "round")
    return available > 0
end

--Both Absorption triggers (the triggered action and the 2+ Malice free version)
--show the text "Absorption", so one handler serves both; the Malice version is
--the one whose ActiveTrigger carries a Malice cost.
--The trigger cannot see the incoming damage type, so the dragon always takes
--the energy in (mode 2 = the "Absorb the Energy" option): turning its own rays
--to the attacker's element is the stat block's intent, and the halving is the same.
MonsterAI:RegisterTrigger{
    id = "Topaz Dragon: Absorption",
    monsters = topazMonster,
    triggers = {"Absorption"},
    description = "Halve typed damage with the triggered action, absorbing the energy into Rays Ignis and Pyro Wave. Pay Malice for the free version only once the triggered action is spent, and only with Malice to spare (or when winded).",
    handler = function(ai, token, triggerInfo)
        local cost = tonumber(triggerInfo.heroicResourceCost) or 0
        if cost <= 0 then
            return {activate = true, mode = 2}
        end
        if TriggeredActionAvailable(token) then
            return {dismiss = true}
        end
        local malice = Malice()
        local winded = token.properties:CurrentHitpoints() <= token.properties:MaxHitpoints()/2
        if malice >= cost and (winded or malice - cost >= 5) then
            return {activate = true, mode = 2}
        end
        return {dismiss = true}
    end,
}

--Collapsing the field costs no Stamina, so it is worth it for anything End
--Effect would end; the shared decision rates the effects.
MonsterAI:RegisterTrigger{
    id = "Topaz Dragon: Collapse Topaz Field",
    monsters = topazMonster,
    abilities = {"Collapse Topaz Field"},
    triggers = {"Collapse Topaz Field"},
    description = "Shrink the field by 2 at the start of the turn to end a save-ends effect bad enough to be worth ending.",
    handler = function(ai, token, triggerInfo)
        if FieldSize(token) < 2 then
            return {dismiss = true}
        end
        local decision = MonsterAI.EndEffectDecision(token, triggerInfo)
        return decision
    end,
}

--------------------------------------------------------------------------------
-- Shared by the later gemstone dragons.
--------------------------------------------------------------------------------

local function EnemiesWithin(token, distance)
    local count = 0
    for _,enemy in ipairs(EnemyTokens(token)) do
        if token:Distance(enemy) <= distance then
            count = count + 1
        end
    end
    return count
end

--Villain Action 2 of every gemstone dragon grows the field and makes it explode
--each round: sooner when enemies already crowd within the new size.
local function RegisterFieldBloom(monsters, abilityName, size, lines)
    MonsterAI:RegisterVillainAction{
        id = monsters[1] .. ": " .. abilityName,
        monsters = monsters,
        abilities = {abilityName},
        description = string.format("Expand the field to a %d aura that explodes each round, sooner when enemies already crowd within %d.", size, size),
        score = function(self, ai, token, ability, context)
            return {score = math.min(1, 0.45 + 0.12*EnemiesWithin(token, size))}
        end,
        execute = function(self, ai, token, scoringInfo, ability, context)
            ai:Speech(token, lines)
            ai.Sleep(0.4)
            ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        end,
    }
end

--Collapsing the field costs no Stamina, so it is worth it for anything End
--Effect would end; the shared decision rates the effects.
local function RegisterFieldCollapse(monsters, gem)
    local name = "Collapse " .. gem .. " Field"
    MonsterAI:RegisterTrigger{
        id = monsters[1] .. ": " .. name,
        monsters = monsters,
        abilities = {name},
        triggers = {name},
        description = "Shrink the field by 2 at the start of the turn to end a save-ends effect bad enough to be worth ending.",
        handler = function(ai, token, triggerInfo)
            if FieldSize(token) < 2 then
                return {dismiss = true}
            end
            return MonsterAI.EndEffectDecision(token, triggerInfo)
        end,
    }
end

--Psi Boost: mode 1 is a double edge, mode 2 extra damage (better when several
--enemies are in reach of an area ability this turn).
local function RegisterPsiBoost(groups, reach, cost, canSpare)
    MonsterAI:RegisterMaliceAbility{
        id = groups[1] .. " Malice: Psi Boost",
        monsterGroups = groups,
        abilities = {"Psi Boost"},
        description = "Spend Malice to empower the next psionic ability: extra damage when enemies are clustered, otherwise a double edge.",
        minimumScore = 0.65,
        score = function(self, ai, token, ability, context)
            if #context.enemyTokens == 0 then
                return nil, "no enemies"
            end
            if canSpare ~= nil and not canSpare(token, cost) then
                return nil, "keeping Malice back"
            end
            local inReach = 0
            for _,enemy in ipairs(context.enemyTokens) do
                if token:Distance(enemy) <= reach + token.properties:CurrentMovementSpeed() then
                    inReach = inReach + 1
                end
            end
            if inReach == 0 then
                return nil, "no enemy within reach of a psionic ability this turn"
            end
            return {score = 0.67, mode = cond(inReach >= 3, 2, 1)}
        end,
        execute = function(self, ai, token, scoringInfo, ability, context)
            ai:ExecuteAbility(token, ability, nil, {sleep = 0.5, symbols = {mode = scoringInfo.mode}})
        end,
    }
end

local function RegisterSoloAction(groups, canSpare)
    MonsterAI:RegisterMaliceAbility{
        id = groups[1] .. " Malice: Solo Action",
        monsterGroups = groups,
        abilities = {"Solo Action"},
        description = "Spend 5 Malice for an extra main action while enemies remain.",
        score = function(self, ai, token, ability, context)
            if #context.enemyTokens == 0 then
                return nil, "no enemies"
            end
            if canSpare ~= nil and not canSpare(token, 5) then
                return nil, "keeping Malice back"
            end
            return {score = 0.78}
        end,
    }
end

--------------------------------------------------------------------------------
-- Emerald Dragon: forced movement, pillars that drag heroes in, Telassault.
--------------------------------------------------------------------------------

local emeraldMonster = {"Emerald Dragon"}
local emeraldGroup = {"Emerald Dragon"}
local PILLAR_KEYWORD = "emeraldpillar"

speech.emerald = {
    ray = {"Come closer.", "Your thoughts are loud. Let me gather them."},
    beacon = {"Stand by my beacons.", "Emerald, rise!"},
    telassault = {"The earth is mine to throw.", "Heads up, little ones."},
    flower = {"Bloom!", "My field opens wide."},
    awe = {"Kneel.", "Look upon me and despair."},
    wash = {"The tide answers me!", "Be swept away!"},
}

MonsterAI:RegisterMove{
    id = "Emerald Dragon: Telekinetic Ray",
    category = "Main Actions",
    monsters = emeraldMonster,
    abilities = {"Telekinetic Ray"},
    description = "Haul every enemy in the best cube toward its centre; spends Malice on a bigger cube when it catches more enemies.",
    score = function(self, ai, token, ability)
        local best = nil
        for mode = 1, 3 do
            local cost = 2*(mode - 1)
            if Malice() - cost >= cond(mode == 1, 0, 5) then
                local radius = ability:GetRadius(token.properties, {mode = mode})
                local plan = FindBestCubePlan(token, ability, nil, radius)
                if plan ~= nil and plan.allies == 0 then
                    local value = plan.enemies - cost*0.3
                    if best == nil or value > best.value then
                        best = {value = value, anchor = plan.anchor, mode = mode, enemies = plan.enemies, radius = radius}
                    end
                end
            end
        end
        if best == nil then
            return nil, "no cube catches an enemy"
        end
        best.score = 0.9 + 0.15*math.min(4, best.enemies)
        return best
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, speech.emerald.ray)
        local area = BuildCubeArea(token, ability, scoringInfo.anchor, scoringInfo.radius)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area), {symbols = {mode = scoringInfo.mode}})
    end,
}

MonsterAI:RegisterMove{
    id = "Emerald Dragon: Emerald Claw",
    category = "Main Actions",
    monsters = emeraldMonster,
    abilities = {"Emerald Claw"},
    description = "Claw two enemies in reach, preferring it to the ray when both claws land.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, function(target, edges)
            if target.isObject then
                return 0.05
            end
            return 1 + (edges or 0)*0.1 + MonsterAI.TargetStaminaBias(target)
        end)
        if loc == nil then
            return nil
        end
        return {score = cond((targetScore or 0) >= 1.8, 1.35, 1.0), loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        table.resize_array(targets, ability:GetNumTargets(token))
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

local function PlanBeacon(token, ability)
    return PlanCrystals(token, ability, PILLAR_KEYWORD, 2, 3)
end

MonsterAI:RegisterMove{
    id = "Emerald Dragon: Emerald Beacon",
    category = "Maneuvers",
    monsters = emeraldMonster,
    abilities = {"Emerald Beacon"},
    description = "Raise two emerald pillars among the enemies so the end-of-round pull keeps dragging them back in.",
    score = function(self, ai, token, ability)
        if #ExistingCrystals(PILLAR_KEYWORD) >= 4 then
            return nil, "four or more pillars already stand"
        end
        local plan = PlanBeacon(token, ability)
        if plan == nil or plan.value < 1 then
            return nil, "no pillar placement reaches an enemy"
        end
        plan.score = 0.75 + 0.05*math.min(4, plan.value)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local anchors = {}
        for _,pillar in ipairs(scoringInfo.spikes) do
            anchors[#anchors+1] = pillar.anchor
        end
        ai:Speech(token, speech.emerald.beacon)
        ai.Sleep(0.3)
        ExecuteMultiCube(ai, token, ability, anchors)
    end,
}

RegisterCubeFollowUps("Emerald Dragon:Emerald Beacon", function(casterToken, abilityClone)
    local plan = PlanBeacon(casterToken, abilityClone)
    return plan ~= nil and plan.spikes[1].anchor or nil
end)

--To Me: drag the furthest enemy the dragon can see into its field and claws.
MonsterAI:RegisterMove{
    id = "Emerald Dragon: To Me",
    category = "Maneuvers",
    monsters = emeraldMonster,
    abilities = {"To Me/Be Gone"},
    description = "Once a turn, pull the furthest visible enemy 8 squares toward the dragon (into the field's bane and claw reach).",
    score = function(self, ai, token, ability)
        local best, bestDistance = nil, 4
        for _,enemy in ipairs(EnemyTokens(token)) do
            local d = token:Distance(enemy)
            if d > bestDistance and d <= ability:GetRange(token.properties) and token:GetLineOfSight(enemy) > 0 then
                best, bestDistance = enemy, d
            end
        end
        if best == nil then
            return nil, "no enemy far enough away to be worth pulling"
        end
        --scored above the main actions so the pull lands before the claws.
        return {score = 1.4, target = best}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:ExecuteAbility(token, ability, {{token = scoringInfo.target}}, {sleep = abilityPause, symbols = {mode = 1}})
    end,
}

MonsterAI:RegisterTrigger{
    id = "Emerald Dragon: Mental Replay",
    monsters = emeraldMonster,
    triggers = {"Mental Replay"},
    description = "Always replay non-rolled damage into the attacker's mind; it is the dragon's only triggered action.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

RegisterFieldCollapse(emeraldMonster, "Emerald")

--Up to count cubes for a volley ability, spread over as many enemies as possible.
local function PlanVolleys(token, ability, count)
    local anchors = {}
    local hits = {}
    for pick = 1, count do
        local plan = FindBestCubePlan(token, ability, function(area, targets)
            local penalty = 0
            for _,info in ipairs(targets) do
                if hits[info.token.charid] then
                    penalty = penalty + 0.5
                end
            end
            return -penalty
        end)
        if plan == nil then
            break
        end
        anchors[#anchors+1] = plan.anchor
        for _,info in ipairs(TokensInArea(token, ability, BuildCubeArea(token, ability, plan.anchor))) do
            hits[info.token.charid] = true
        end
    end
    local n = 0
    for _ in pairs(hits) do
        n = n + 1
    end
    return anchors, n
end

MonsterAI:RegisterVillainAction{
    id = "Emerald Dragon: Telassault",
    monsters = emeraldMonster,
    abilities = {"Telassault"},
    description = "Hurl three chunks of the battlefield at the three best 3 cubes, spreading them over as many enemies as possible.",
    score = function(self, ai, token, ability, context)
        local anchors, enemies = PlanVolleys(token, ability, 3)
        if #anchors == 0 then
            return nil
        end
        return {score = math.min(1, 0.35 + 0.15*enemies)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.emerald.telassault)
        ai.Sleep(0.4)
        local anchors = PlanVolleys(token, ability, 3)
        if #anchors == 0 then
            return
        end
        ExecuteMultiCube(ai, token, ability, anchors)
    end,
}

RegisterCubeFollowUps("Emerald Dragon:Telassault", function(casterToken, abilityClone)
    local plan = FindBestCubePlan(casterToken, abilityClone)
    return plan ~= nil and plan.anchor or nil
end)

RegisterFieldBloom(emeraldMonster, "Emerald Flower", 6, speech.emerald.flower)

MonsterAI:RegisterVillainAction{
    id = "Emerald Dragon: Awe",
    monsters = emeraldMonster,
    abilities = {"Awe"},
    description = "Terrify every enemy within 10.",
    score = function(self, ai, token, ability, context)
        local n = EnemiesWithin(token, 10)
        if n == 0 then
            return nil
        end
        return {score = math.min(1, 0.3 + 0.15*n)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.emerald.awe)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--Malice the Emerald Dragon keeps for Wash Away once enough enemies crowd it.
local function EmeraldCanSpare(token, cost)
    local reserve = 0
    if Malice() >= 7 and EnemiesWithin(token, 3) >= 3 then
        reserve = 7
    end
    return Malice() - cost >= reserve
end

RegisterPsiBoost(emeraldGroup, 10, 3, EmeraldCanSpare)
RegisterSoloAction(emeraldGroup, EmeraldCanSpare)

MonsterAI:RegisterMaliceAbility{
    id = "Emerald Dragon Malice: Terravolley",
    monsterGroups = emeraldGroup,
    abilities = {"Terravolley"},
    description = "Hurl a chunk of the map at the cube holding the most enemies, bigger (and harder) with spare Malice.",
    score = function(self, ai, token, ability, context)
        local best = nil
        for mode = 1, 4 do
            local cost = 2 + mode
            if EmeraldCanSpare(token, cost) then
                local radius = ability:GetRadius(token.properties, {mode = mode})
                local plan = FindBestCubePlan(token, ability, nil, radius)
                if plan ~= nil and plan.allies == 0 then
                    local value = plan.enemies - (mode - 1)*0.4
                    if best == nil or value > best.value then
                        best = {value = value, anchor = plan.anchor, mode = mode, radius = radius, enemies = plan.enemies}
                    end
                end
            end
        end
        if best == nil or best.enemies < 2 then
            return nil, "no cube holds two or more enemies"
        end
        best.score = math.min(0.9, 0.6 + 0.07*best.enemies)
        return best
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildCubeArea(token, ability, scoringInfo.anchor, scoringInfo.radius)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area), {symbols = {mode = scoringInfo.mode}})
    end,
}

--Wash Away: when enemies crowd the dragon, flush everyone 25 squares in the
--direction that carries most enemies away from it. Modes: North, South, East, West.
local WASH_DIRS = { {0, 1}, {0, -1}, {1, 0}, {-1, 0} }
MonsterAI:RegisterMaliceAbility{
    id = "Emerald Dragon Malice: Wash Away",
    monsterGroups = emeraldGroup,
    abilities = {"Wash Away"},
    description = "When three or more enemies crowd within 3, wash them all 25 squares away in the direction that scatters the most.",
    score = function(self, ai, token, ability, context)
        if EnemiesWithin(token, 3) < 3 then
            return nil, "fewer than three enemies crowd the dragon"
        end
        local best, bestScore = 1, -1
        for i,d in ipairs(WASH_DIRS) do
            local score = 0
            for _,enemy in ipairs(EnemyTokens(token)) do
                local dx, dy = enemy.loc.x - token.loc.x, enemy.loc.y - token.loc.y
                if dx*d[1] + dy*d[2] > 0 then
                    score = score + 1
                end
            end
            if score > bestScore then
                best, bestScore = i, score
            end
        end
        return {score = 0.8, mode = best}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.emerald.wash)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause, symbols = {mode = scoringInfo.mode}})
    end,
}

--------------------------------------------------------------------------------
-- Ruby Dragon: reality warping, crystal walls, materialized monoliths.
--------------------------------------------------------------------------------

local rubyMonster = {"Ruby Dragon"}
local rubyGroup = {"Ruby Dragon"}
local MONOLITH_KEYWORD = "rubymonolith"

speech.ruby = {
    realitas = {"Reality bends to me.", "Lie down. Stay down."},
    wave = {"Crystal, rise!", "There is no way out."},
    volley = {"Burn in your own minds!", "Six fires, one mind."},
    bloom = {"My field blooms!", "Reality, unfold!"},
    shatter = {"Shatter!", "Your reality breaks with mine."},
    rewrite = {"I rewrite the world.", "Let us start again, on my terms."},
}

--Squares occupied by any creature or object, keyed "x,y".
local function OccupiedSquares()
    local occupied = {}
    for _,tok in ipairs(dmhub.allTokensIncludingObjects) do
        if tok.valid then
            for _,l in ipairs(tok:LocsOccupyingWhenAt(tok.loc) or {}) do
                occupied[string.format("%d,%d", l.x, l.y)] = true
            end
        end
    end
    return occupied
end

local function HasEffect(token, name)
    return (tonumber(ExecuteGoblinScript(string.format('Stacks("%s")', name), token.properties:LookupSymbol{}, 0, "Ruby AI")) or 0) > 0
end

--The field's start-of-turn shape: hazardous ground when enemies stand in the
--field, monoliths for cover against enemies holding back at range, otherwise
--difficult ground to keep them from escaping.
MonsterAI:RegisterTrigger{
    id = "Ruby Dragon: Ruby Field",
    monsters = rubyMonster,
    triggers = {"Ruby Field"},
    description = "Hazard when two or more enemies are in the field, monoliths when two or more enemies keep their distance, otherwise difficult terrain.",
    handler = function(ai, token, triggerInfo)
        local field = FieldSize(token)
        if EnemiesWithin(token, field) >= 2 then
            return {activate = true, mode = 2}
        end
        local far = #EnemyTokens(token) - EnemiesWithin(token, 6)
        if far >= 2 and #ExistingCrystals(MONOLITH_KEYWORD) < 6 then
            return {activate = true, mode = cond(HasEffect(token, "Ruby Bloom"), 4, 3)}
        end
        return {activate = true, mode = 1}
    end,
}

--Monoliths go between the dragon and the enemies furthest away, as cover.
local g_monolithPlan = {}
MonsterAI:RegisterPrompt{
    prompts = {"Ruby Dragon:Ruby Field: Materialize"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = g_monolithPlan[casterToken.charid]
        if plan == nil or plan.used >= #plan.anchors then
            local radius = tonumber(abilityClone:GetRadius(casterToken.properties)) or 2
            local reach = math.max(1, FieldSize(casterToken) - radius + 1)
            local enemies = EnemyTokens(casterToken)
            table.sort(enemies, function(a, b) return casterToken:Distance(a) > casterToken:Distance(b) end)
            local occupied = OccupiedSquares()
            local anchors = {}
            for _,enemy in ipairs(enemies) do
                local dx, dy = enemy.loc.x - casterToken.loc.x, enemy.loc.y - casterToken.loc.y
                local len = math.max(1, math.max(math.abs(dx), math.abs(dy)))
                for step = reach, 1, -1 do
                    local anchor = casterToken.loc:dir(math.floor(dx*step/len + 0.5), math.floor(dy*step/len + 0.5))
                    local area = BuildCubeArea(casterToken, abilityClone, anchor, radius)
                    local free = #(area.locations or {}) > 0
                    for _,l in ipairs(area.locations or {}) do
                        if occupied[string.format("%d,%d", l.x, l.y)] then free = false end
                    end
                    if free then
                        anchors[#anchors+1] = anchor
                        for _,l in ipairs(area.locations or {}) do
                            occupied[string.format("%d,%d", l.x, l.y)] = true
                        end
                        break
                    end
                end
            end
            plan = {anchors = anchors, used = 0}
            g_monolithPlan[casterToken.charid] = plan
        end
        plan.used = plan.used + 1
        local anchor = plan.anchors[plan.used]
        if anchor == nil then
            return {targets = {}}
        end
        local area = BuildCubeArea(casterToken, abilityClone, anchor)
        symbols.targetArea = area
        return {targets = {}, targetArea = area}
    end,
}

MonsterAI:RegisterMove{
    id = "Ruby Dragon: Glimpse",
    category = "Maneuvers",
    monsters = rubyMonster,
    abilities = {"Glimpse"},
    description = "Once a turn, show the healthiest visible enemy a glimpse of warped reality (a double bane or 10 corruption on their next power roll).",
    score = function(self, ai, token, ability)
        local best, bestStamina = nil, -1
        for _,enemy in ipairs(EnemyTokens(token)) do
            if token:Distance(enemy) <= ability:GetRange(token.properties) and token:GetLineOfSight(enemy) > 0
                and not HasEffect(enemy, "Glimpse") then
                local stamina = enemy.properties:CurrentHitpoints()
                if stamina > bestStamina then
                    best, bestStamina = enemy, stamina
                end
            end
        end
        if best == nil then
            return nil, "no visible enemy without a glimpse"
        end
        return {score = 1.45, target = best}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:ExecuteAbility(token, ability, {{token = scoringInfo.target}}, {sleep = abilityPause})
    end,
}

--Warp mode for Rays Realitas: 1 none, 3 drop 2 (2 Malice) when Malice allows.
local function RealitasMode()
    if Malice() >= 7 then
        return 3
    elseif Malice() >= 4 then
        return 2
    end
    return 1
end

MonsterAI:RegisterMove{
    id = "Ruby Dragon: Rays Realitas",
    category = "Main Actions",
    monsters = rubyMonster,
    abilities = {"Rays Realitas"},
    description = "Knock a line of enemies prone into warped ground, dropping the ground under them when Malice is spare.",
    score = function(self, ai, token, ability)
        local plan = FindBestLinePlan(ai, token, ability, nil)
        if plan == nil or plan.allies > 0 then
            return nil, "no line catches enemies without allies"
        end
        plan.score = 0.9 + 0.2*math.min(4, plan.enemies)
        plan.mode = RealitasMode()
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ai:Speech(token, speech.ruby.realitas)
        local area = BuildLineArea(token, ability, token.loc, scoringInfo.targetLoc)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area), {symbols = {mode = scoringInfo.mode}})
    end,
}

MonsterAI:RegisterMove{
    id = "Ruby Dragon: Ruby Claw",
    category = "Main Actions",
    monsters = rubyMonster,
    abilities = {"Ruby Claw"},
    description = "Melt the legs of two enemies in reach, preferring enemies it has already clawed (the potency grows).",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, function(target, edges)
            if target.isObject then
                return 0.05
            end
            local melted = tonumber(ExecuteGoblinScript('Stacks("Ruby Melt")', target.properties:LookupSymbol{}, 0, "Ruby AI")) or 0
            return 1 + (edges or 0)*0.1 + 0.1*math.min(3, melted) + MonsterAI.TargetStaminaBias(target)
        end)
        if loc == nil then
            return nil
        end
        return {score = cond((targetScore or 0) >= 1.8, 1.4, 1.0), loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        table.resize_array(targets, ability:GetNumTargets(token))
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

--Up to 10 empty squares in a line just beyond the enemies (as seen from the
--dragon), at right angles to the dragon's line to them: a crystal wall at
--their backs. Returns a target list of {loc}.
local function PlanWall(token, range)
    local enemies = {}
    for _,enemy in ipairs(EnemyTokens(token)) do
        if token:Distance(enemy) <= range then
            enemies[#enemies+1] = enemy
        end
    end
    if #enemies == 0 then
        return nil
    end
    local cx, cy = 0, 0
    for _,enemy in ipairs(enemies) do
        cx = cx + enemy.loc.x
        cy = cy + enemy.loc.y
    end
    cx, cy = cx/#enemies, cy/#enemies
    local ux, uy = cx - token.loc.x, cy - token.loc.y
    local len = math.sqrt(ux*ux + uy*uy)
    if len < 0.5 then
        ux, uy, len = 1, 0, 1
    end
    ux, uy = ux/len, uy/len
    local mx, my = cx + ux*2, cy + uy*2
    local px, py = -uy, ux
    local occupied = OccupiedSquares()
    local squares = {}
    local seen = {}
    for k = -5, 5 do
        local loc = token.loc:dir(math.floor(mx + px*k + 0.5) - token.loc.x, math.floor(my + py*k + 0.5) - token.loc.y)
        local key = string.format("%d,%d", loc.x, loc.y)
        if not seen[key] then
            seen[key] = true
            if occupied[key] or token:Distance(loc) > range then
                --keep the wall contiguous: stop at the first gap once it has started.
                if #squares > 0 then
                    break
                end
            else
                squares[#squares+1] = {loc = loc}
                if #squares >= 10 then
                    break
                end
            end
        end
    end
    if #squares < 3 then
        return nil
    end
    return squares
end

MonsterAI:RegisterMove{
    id = "Ruby Dragon: Ruby Wave",
    category = "Maneuvers",
    monsters = rubyMonster,
    abilities = {"Ruby Wave"},
    description = "Raise a crystal wall at the enemies' backs so they cannot fall back from the dragon.",
    score = function(self, ai, token, ability)
        if #ExistingCrystals("rubywall") >= 20 then
            return nil, "enough crystal walls stand"
        end
        local squares = PlanWall(token, ability:GetRange(token.properties))
        if squares == nil then
            return nil, "no room for a wall behind the enemies"
        end
        return {score = 0.72, squares = squares}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, speech.ruby.wave)
        local squares = PlanWall(token, ability:GetRange(token.properties)) or scoringInfo.squares
        ai:ExecuteAbility(token, ability, squares, {sleep = abilityPause})
    end,
}

--Shattered Reality's invoked walls and ray.
MonsterAI:RegisterPrompt{
    prompts = {"Ruby Dragon:Ruby Wave"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local squares = PlanWall(casterToken, abilityClone:GetRange(casterToken.properties))
        if squares == nil then
            return {targets = {}}
        end
        return {targets = squares}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Ruby Dragon:Rays Realitas"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local candidates = {}
        for _,enemy in ipairs(EnemyTokens(casterToken)) do
            candidates[#candidates+1] = {targetLoc = enemy.loc, locOverride = casterToken.loc, cost = 0}
        end
        local plan = ai:FindBestLinePlan(casterToken, abilityClone, {candidates = candidates, logPlan = false,
            scorefn = function(target, candidate)
                if not LiveCreature(target) or target.charid == casterToken.charid then return 0 end
                return cond(target:IsFriend(casterToken), -2, 1)
            end})
        if plan == nil then
            return nil
        end
        local area = BuildLineArea(casterToken, abilityClone, casterToken.loc, plan.targetLoc)
        symbols.targetArea = area
        return {targets = TokensInArea(casterToken, abilityClone, area), targetArea = area}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Ruby Dragon: Reality Check",
    monsters = rubyMonster,
    triggers = {"Reality Check"},
    description = "Always punish a creature that taunts or frightens the dragon.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Ruby Dragon: I Know Your Tricks",
    monsters = rubyMonster,
    triggers = {"I Know Your Tricks"},
    description = "Spend 1 Malice to adopt the attacker's damage type as the dragon's immunity while Malice is comfortable.",
    handler = function(ai, token, triggerInfo)
        if Malice() >= 4 then
            return {activate = true}
        end
        return {dismiss = true}
    end,
}

RegisterFieldCollapse(rubyMonster, "Ruby")

MonsterAI:RegisterVillainAction{
    id = "Ruby Dragon: Psionic Volley",
    monsters = rubyMonster,
    abilities = {"Psionic Volley"},
    description = "Rain six burning 2 cubes over as many enemies as possible.",
    score = function(self, ai, token, ability, context)
        local anchors, enemies = PlanVolleys(token, ability, 6)
        if #anchors == 0 then
            return nil
        end
        return {score = math.min(1, 0.35 + 0.15*enemies)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.ruby.volley)
        ai.Sleep(0.4)
        local anchors = PlanVolleys(token, ability, 6)
        if #anchors == 0 then
            return
        end
        ExecuteMultiCube(ai, token, ability, anchors)
    end,
}

RegisterCubeFollowUps("Ruby Dragon:Psionic Volley", function(casterToken, abilityClone)
    local plan = FindBestCubePlan(casterToken, abilityClone)
    return plan ~= nil and plan.anchor or nil
end)

RegisterFieldBloom(rubyMonster, "Ruby Bloom", 6, speech.ruby.bloom)

MonsterAI:RegisterVillainAction{
    id = "Ruby Dragon: Shattered Reality",
    monsters = rubyMonster,
    abilities = {"Shattered Reality"},
    description = "Wall the enemies in, fire Rays Realitas, then shatter every crystal wall on the map.",
    score = function(self, ai, token, ability, context)
        local n = EnemiesWithin(token, 10)
        if n == 0 then
            return nil
        end
        return {score = math.min(1, 0.3 + 0.15*n)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.ruby.shatter)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

RegisterPsiBoost(rubyGroup, 5, 3, nil)
RegisterSoloAction(rubyGroup, nil)

--The most heroic resources or surges any enemy in line of effect holds: the
--number Thoughts Manifest doubles (the script picks the same creature).
local function MostCharged(token)
    local best = 0
    for _,enemy in ipairs(EnemyTokens(token)) do
        if token:GetLineOfSight(enemy) > 0 then
            pcall(function() best = math.max(best, tonumber(enemy.properties:GetAvailableSurges()) or 0) end)
            if enemy.properties:IsHero() then
                pcall(function() best = math.max(best, tonumber(enemy.properties:GetHeroicOrMaliceResources()) or 0) end)
            end
        end
    end
    return best
end

MonsterAI:RegisterMaliceAbility{
    id = "Ruby Dragon Malice: Thoughts Manifest",
    monsterGroups = rubyGroup,
    abilities = {"Thoughts Manifest"},
    description = "Turn the most charged-up enemy's heroic resources or surges into damage on a 3 cube of enemies.",
    score = function(self, ai, token, ability, context)
        local charged = MostCharged(token)
        if charged < 3 then
            return nil, "no enemy holds three or more heroic resources or surges"
        end
        local plan = FindBestCubePlan(token, ability)
        if plan == nil or plan.enemies < 2 or plan.allies > 0 then
            return nil, "no cube holds two enemies"
        end
        return {score = math.min(0.9, 0.6 + 0.03*charged*plan.enemies), anchor = plan.anchor}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildCubeArea(token, ability, scoringInfo.anchor)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area))
    end,
}

--Reality Rewrite sets everyone to their winded value, the dragon included: worth
--it when the heroes would lose far more than they gain, or the dragon is low.
local function RewriteValue(token)
    local value = 0
    for _,tok in ipairs(dmhub.allTokens) do
        if LiveCreature(tok) then
            local p = tok.properties
            local change = math.floor(p:MaxHitpoints()/2) - p:CurrentHitpoints()
            if tok.charid == token.charid or tok:IsFriend(token) then
                value = value + change
            else
                value = value - change
            end
        end
    end
    return value
end

MonsterAI:RegisterMaliceAbility{
    id = "Ruby Dragon Malice: Reality Rewrite",
    monsterGroups = rubyGroup,
    abilities = {"Reality Rewrite"},
    description = "Rewrite everyone to their winded Stamina when the heroes lose much more than the dragon (60+ Stamina swing).",
    score = function(self, ai, token, ability, context)
        local value = RewriteValue(token)
        if value < 60 then
            return nil, string.format("a swing of only %d Stamina", value)
        end
        return {score = math.min(0.95, 0.7 + value/600)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.ruby.rewrite)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Sapphire Dragon: time. Rejuvenation, accelerating rays, growing crystals.
--------------------------------------------------------------------------------

local sapphireMonster = {"Sapphire Dragon"}
local sapphireGroup = {"Sapphire Dragon"}

speech.sapphire = {
    ray = {"Faster. Faster!", "Run out of time."},
    rejuvenate = {"I have all the time in the world.", "Again."},
    roar = {"Hear the years roar!", "Echo, and echo, and echo."},
    star = {"Shine, Star Sapphire!", "Time breaks open."},
    warp = {"Let me show you your future.", "Be what you were."},
}

MonsterAI:RegisterMove{
    id = "Sapphire Dragon: Chronokinetic Ray",
    category = "Main Actions",
    monsters = sapphireMonster,
    abilities = {"Chronokinetic Ray"},
    description = "Accelerate the enemies in the best 4 cube.",
    score = function(self, ai, token, ability)
        local plan = FindBestCubePlan(token, ability)
        if plan == nil or plan.allies > 0 then
            return nil, "no cube catches enemies without allies"
        end
        return {score = 0.95 + 0.15*math.min(4, plan.enemies), anchor = plan.anchor}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, speech.sapphire.ray)
        local area = BuildCubeArea(token, ability, scoringInfo.anchor)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area))
    end,
}

MonsterAI:RegisterMove{
    id = "Sapphire Dragon: Crush",
    category = "Main Actions",
    monsters = sapphireMonster,
    abilities = {"Crush"},
    description = "Crush two enemies in reach, preferred when both are in reach.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, function(target, edges)
            if target.isObject then
                return 0.05
            end
            return 1 + (edges or 0)*0.1 + MonsterAI.TargetStaminaBias(target)
        end)
        if loc == nil then
            return nil
        end
        return {score = cond((targetScore or 0) >= 1.8, 1.4, 1.0), loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        table.resize_array(targets, ability:GetNumTargets(token))
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Sapphire Dragon: Rejuvenate",
    category = "Maneuvers",
    monsters = sapphireMonster,
    abilities = {"Rejuvenate"},
    description = "Regain 100 Stamina whenever the dragon is missing at least 100.",
    score = function(self, ai, token, ability)
        local p = token.properties
        if p:MaxHitpoints() - p:CurrentHitpoints() < 100 then
            return nil, "missing less than 100 Stamina"
        end
        return {score = 1.5}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, speech.sapphire.rejuvenate)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterTrigger{
    id = "Sapphire Dragon: Not So Fast",
    monsters = sapphireMonster,
    triggers = {"Not So Fast"},
    description = "Always slow and toss a creature that charges the dragon (a free triggered action).",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Sapphire Dragon: Time Decay",
    monsters = sapphireMonster,
    triggers = {"Time Decay"},
    description = "Decay any creature that targets the dragon a second time; the dragon's only triggered action.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

RegisterFieldCollapse(sapphireMonster, "Sapphire")

MonsterAI:RegisterVillainAction{
    id = "Sapphire Dragon: Roar of Time",
    monsters = sapphireMonster,
    abilities = {"Roar of Time"},
    description = "Echo every enemy within 10.",
    score = function(self, ai, token, ability, context)
        local n = EnemiesWithin(token, 10)
        if n == 0 then
            return nil
        end
        return {score = math.min(1, 0.3 + 0.15*n)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.sapphire.roar)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

RegisterFieldBloom(sapphireMonster, "Star Sapphire", 6, speech.sapphire.star)

MonsterAI:RegisterVillainAction{
    id = "Sapphire Dragon: Time Warp",
    monsters = sapphireMonster,
    abilities = {"Time Warp"},
    description = "Warp the age of the healthiest enemy within 10.",
    score = function(self, ai, token, ability, context)
        local best, bestStamina = nil, -1
        for _,enemy in ipairs(EnemyTokens(token)) do
            if token:Distance(enemy) <= 10 and token:GetLineOfSight(enemy) > 0 and enemy.properties:CurrentHitpoints() > bestStamina then
                best, bestStamina = enemy, enemy.properties:CurrentHitpoints()
            end
        end
        if best == nil then
            return nil
        end
        return {score = 0.8, target = best}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.sapphire.warp)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, {{token = scoringInfo.target}}, {sleep = abilityPause})
    end,
}

RegisterSoloAction(sapphireGroup, nil)

MonsterAI:RegisterMaliceAbility{
    id = "Sapphire Dragon Malice: Wait",
    monsterGroups = sapphireGroup,
    abilities = {"Wait"},
    description = "Bank Malice (2 for 4) while it is too low for anything else.",
    score = function(self, ai, token, ability, context)
        if Malice() >= 5 then
            return nil, "enough Malice for a real feature"
        end
        return {score = 0.66}
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Sapphire Dragon Malice: Solo Turn",
    monsterGroups = sapphireGroup,
    abilities = {"Solo Turn"},
    description = "Take an extra turn this round when Malice allows and enemies are in reach.",
    score = function(self, ai, token, ability, context)
        if EnemiesWithin(token, 25) == 0 then
            return nil, "no enemy in reach"
        end
        return {score = 0.85}
    end,
}

--The unoccupied square next to the most enemies (within 2), for a crystal seed.
local function PlanFlowerSeed(token, range)
    local occupied = OccupiedSquares()
    local enemies = EnemyTokens(token)
    local best, bestScore = nil, 0
    for _,enemy in ipairs(enemies) do
        for dx = -2, 2 do
            for dy = -2, 2 do
                local loc = enemy.loc:dir(dx, dy)
                if not occupied[string.format("%d,%d", loc.x, loc.y)] and token:Distance(loc) <= range then
                    local score = 0
                    for _,other in ipairs(enemies) do
                        if other.loc:DistanceInTiles(loc) <= 2 then
                            score = score + 1
                        end
                    end
                    if score > bestScore then
                        best, bestScore = loc, score
                    end
                end
            end
        end
    end
    return best, bestScore
end

MonsterAI:RegisterMaliceAbility{
    id = "Sapphire Dragon Malice: Sapphire Flower",
    monsterGroups = sapphireGroup,
    abilities = {"Sapphire Flower"},
    description = "Seed a growing sapphire crystal beside the tightest knot of enemies.",
    score = function(self, ai, token, ability, context)
        if #ExistingCrystals("sapphirecrystal") >= 20 then
            return nil, "the map is already full of crystal"
        end
        local seed, n = PlanFlowerSeed(token, ability:GetRange(token.properties))
        if seed == nil or n < 2 then
            return nil, "no square near two or more enemies"
        end
        return {score = 0.72, seed = seed}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildCubeArea(token, ability, scoringInfo.seed)
        ExecuteAreaAbility(ai, token, ability, area, {})
    end,
}

--------------------------------------------------------------------------------
-- Amethyst Dragon: souls. Shared pain, entanglement, crystal echoes.
--------------------------------------------------------------------------------

local amethystMonster = {"Amethyst Dragon"}
local amethystGroup = {"Amethyst Dragon"}

speech.amethyst = {
    animus = {"Share it all.", "One soul, many bodies."},
    echoes = {"Another of me.", "Which one is real?"},
    lance = {"Pierce!", "Be still."},
    flash = {"Flash!", "My field burns bright."},
    pieces = {"Pieces of me, all of me!", "We are legion."},
}

MonsterAI:RegisterMove{
    id = "Amethyst Dragon: Rays Animus",
    category = "Main Actions",
    monsters = amethystMonster,
    abilities = {"Rays Animus"},
    description = "Soul link every enemy in the 6 cube next to the dragon, moving first to catch the most.",
    score = function(self, ai, token, ability)
        local plan = FindBestCubePlan(token, ability)
        if plan == nil then
            return nil, "no enemy close enough to the dragon"
        end
        return {score = 0.95 + 0.2*math.min(4, plan.enemies), anchor = plan.anchor}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, speech.amethyst.animus)
        local area = BuildCubeArea(token, ability, scoringInfo.anchor)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area))
    end,
}

MonsterAI:RegisterMove{
    id = "Amethyst Dragon: Amethyst Claw",
    category = "Main Actions",
    monsters = amethystMonster,
    abilities = {"Amethyst Claw"},
    description = "Claw two enemies in reach.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, function(target, edges)
            if target.isObject then
                return 0.05
            end
            return 1 + (edges or 0)*0.1 + MonsterAI.TargetStaminaBias(target)
        end)
        if loc == nil then
            return nil
        end
        return {score = cond((targetScore or 0) >= 1.8, 1.35, 1.0), loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        table.resize_array(targets, ability:GetNumTargets(token))
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

local function EchoCount()
    local n = 0
    for _,tok in ipairs(dmhub.allTokens) do
        if LiveCreature(tok) and (tok.properties:try_get("keywords") or {})["Amethyst Echo"] then
            n = n + 1
        end
    end
    return n
end

--An unoccupied square beside an enemy the dragon is not already next to.
local function EchoSpot(token)
    local occupied = OccupiedSquares()
    for _,enemy in ipairs(EnemyTokens(token)) do
        if token:Distance(enemy) > 2 then
            for dx = -4, 4 do
                for dy = -4, 4 do
                    local loc = enemy.loc:dir(dx, dy)
                    if token:Distance(loc) <= 10 and enemy.loc:DistanceInTiles(loc) >= 3 then
                        local free = true
                        for ox = 0, 3 do
                            for oy = 0, 3 do
                                if occupied[string.format("%d,%d", loc.x + ox, loc.y - oy)] then free = false end
                            end
                        end
                        if free then
                            return loc
                        end
                    end
                end
            end
        end
    end
    return nil
end

MonsterAI:RegisterMove{
    id = "Amethyst Dragon: Amethyst Echoes",
    category = "Maneuvers",
    monsters = amethystMonster,
    abilities = {"Amethyst Echoes"},
    description = "Spend 3 Malice for a crystalline duplicate beside an enemy the dragon cannot reach, up to two at a time.",
    score = function(self, ai, token, ability)
        if EchoCount() >= 2 then
            return nil, "two duplicates already"
        end
        local spot = EchoSpot(token)
        if spot == nil then
            return nil, "no open space near a distant enemy"
        end
        return {score = 0.8, spot = spot}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, speech.amethyst.echoes)
        ai:ExecuteAbility(token, ability, {{loc = scoringInfo.spot}}, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterTrigger{
    id = "Amethyst Dragon: Soul Shield",
    monsters = amethystMonster,
    triggers = {"Soul Shield"},
    description = "Pass a taunt or fright on to the entangled creature whenever one is entangled.",
    handler = function(ai, token, triggerInfo)
        for _,tok in ipairs(dmhub.allTokens) do
            if LiveCreature(tok) and (tonumber(ExecuteGoblinScript('Stacks("Entangled")', tok.properties:LookupSymbol{}, 0, "Amethyst AI")) or 0) > 0 then
                return {activate = true}
            end
        end
        return {dismiss = true}
    end,
}

RegisterFieldCollapse(amethystMonster, "Amethyst")

MonsterAI:RegisterVillainAction{
    id = "Amethyst Dragon: Spirit Lance",
    monsters = amethystMonster,
    abilities = {"Spirit Lance"},
    description = "Daze the best line of enemies within 10.",
    score = function(self, ai, token, ability, context)
        local plan = FindBestLinePlan(ai, token, ability, nil)
        if plan == nil then
            return nil
        end
        return {score = math.min(1, 0.35 + 0.15*plan.enemies)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.amethyst.lance)
        ai.Sleep(0.4)
        local candidates = {}
        for _,enemy in ipairs(EnemyTokens(token)) do
            candidates[#candidates+1] = {targetLoc = enemy.loc, locOverride = token.loc, cost = 0}
        end
        local plan = ai:FindBestLinePlan(token, ability, {candidates = candidates, logPlan = false,
            scorefn = function(target, candidate)
                if not LiveCreature(target) or target.charid == token.charid then return 0 end
                return cond(target:IsFriend(token), -2, 1)
            end})
        if plan == nil then
            return
        end
        local area = BuildLineArea(token, ability, token.loc, plan.targetLoc)
        ExecuteAreaAbility(ai, token, ability, area, TokensInArea(token, ability, area))
    end,
}

RegisterFieldBloom(amethystMonster, "Amethyst Flash", 6, speech.amethyst.flash)

MonsterAI:RegisterVillainAction{
    id = "Amethyst Dragon: Pieces of Me, All of Me",
    monsters = amethystMonster,
    abilities = {"Pieces of Me, All of Me"},
    description = "Splinter into four crystal fragments next to the enemies.",
    score = function(self, ai, token, ability, context)
        local spot = EchoSpot(token)
        if spot == nil then
            return nil
        end
        return {score = 0.8, spot = spot}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.amethyst.pieces)
        ai.Sleep(0.4)
        ai:ExecuteAbility(token, ability, {{loc = EchoSpot(token) or scoringInfo.spot}}, {sleep = abilityPause})
    end,
}

RegisterPsiBoost(amethystGroup, 7, 2, nil)
RegisterSoloAction(amethystGroup, nil)

MonsterAI:RegisterMaliceAbility{
    id = "Amethyst Dragon Malice: Anima Chain",
    monsterGroups = amethystGroup,
    abilities = {"Anima Chain"},
    description = "Chain the dragon's soul to the heroes' once two or more are soul linked, so its wounds become theirs.",
    score = function(self, ai, token, ability, context)
        local linked = 0
        for _,enemy in ipairs(EnemyTokens(token)) do
            if (tonumber(ExecuteGoblinScript('Stacks("Soul Linked")', enemy.properties:LookupSymbol{}, 0, "Amethyst AI")) or 0) > 0 then
                linked = linked + 1
            end
        end
        if linked < 2 then
            return nil, "fewer than two enemies are soul linked"
        end
        return {score = 0.85}
    end,
}
