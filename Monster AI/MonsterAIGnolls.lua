local mod = dmhub.GetModLoading()

--Monster AI for the gnoll band: the Abyssal Hyena, Chainflail, Mage Mauler and
--Wildling minions, the Abyssal Archer, Abyssal Summoner, Cackler,
--Bonesplitter and Marauder, the Tusker Demon, the Gnoll Carnage leader, and
--the band's Malice features (Iron Jaws, Bloodpool, Echoes of Laughter).
--
--What makes gnolls gnolls is the Cackletongue chain. Every non-minion gnoll
--has its own Cackletongue maneuver, and when one goes off, each ally it
--reaches that has not used theirs this round may use theirs at once for free.
--In the data that offer is a "Cackletongue" trigger prompt on each of those
--allies; accepting it casts "Use Cackletongue", which hands the gnoll a free
--copy of its own Cackletongue to aim. So:
--  * One gnoll pays for the opening Cackletongue when the whole chain it would
--    set off (see CascadeValue) is worth the Malice.
--  * Every gnoll answers its Cackletongue prompt (and the targeting that
--    follows) itself, whether the chain was started by the AI or by the
--    Director.
--  * The AI's own turn waits for the chain to finish (ResolveCackletongueCascade)
--    instead of leaving the prompts until the turn is over.
--Minion signature strikes are left to the shared squad logic. The death
--triggers (Death Frenzy, Death Circle, Death Rampage) and the Carnage's
--villain actions move gnolls in next to the enemy for free strikes.

local movementPause = 0.6
local stationaryPause = 0.35
local speechPause = 0.45
local abilityPause = 0.9
local grantedActionPause = 0.5

--Custom triggers reach a gnoll a frame or more after the cast that fires
--them, so the chain is only over once no new prompt has shown up for this long.
local cascadeSettleSeconds = 1.5
local cascadeTimeoutSeconds = 90

local gnollGroup = {"Gnoll"}

local gnollMonsters = {
    "Abyssal Hyena",
    "Gnoll Chainflail",
    "Gnoll Mage Mauler",
    "Gnoll Wildling",
    "Gnoll Abyssal Archer",
    "Gnoll Abyssal Summoner",
    "Gnoll Cackler",
    "Gnoll Bonesplitter",
    "Gnoll Marauder",
    "Tusker Demon",
    "Gnoll Carnage",
}

local gnollMonsterSet = {}
for _,monsterType in ipairs(gnollMonsters) do
    gnollMonsterSet[monsterType] = true
end

--Each stat block's own Cackletongue maneuver.
local cackletongueAbilities = {
    ["Gnoll Abyssal Archer"] = "Archer's Cackletongue",
    ["Gnoll Abyssal Summoner"] = "Summoner's Cackletongue",
    ["Gnoll Cackler"] = "Cackler's Cackletongue",
    ["Gnoll Bonesplitter"] = "Bonesplitter's Cackletongue",
    ["Gnoll Marauder"] = "Marauder's Cackletongue",
    ["Gnoll Carnage"] = "Carnage's Cackletongue",
}

local cackletongueMonsters = {}
for monsterType,_ in pairs(cackletongueAbilities) do
    cackletongueMonsters[#cackletongueMonsters+1] = monsterType
end
table.sort(cackletongueMonsters)

--"Used Cackletongue": put on a gnoll by its own Cackletongue, and what stops
--the chain offering that gnoll another one this round.
local usedCackletongueEffectId = "bca3f902-ace6-4b39-9f6c-be4a86824e7d"
local echoesOfLaughterEffectId = "3c0e261c-528b-4855-acff-1d29c25ec4ab"

--What each Cackletongue is worth, in rough points of damage, per creature it
--helps. A chain is opened only when it is worth at least
--cackletongueValuePerMalice points for each point of Malice it costs.
local cackletongueValues = {
    edge = {nonMinion = 1.5, minion = 0.75},         --Archer's: edge on the next strike
    extraDamage = {nonMinion = 3, minion = 1.5},     --Carnage's: +3 damage on the next strike
    shift = 1.5,                                     --Marauder's: a shift to somewhere better
    freeStrike = 2.5,                                --Bonesplitter's: a free strike
    frightened = 1.5,                                --Cackler's: per enemy who may end up frightened
    transform = 4,                                   --Summoner's: an abyssal hyena becomes a marauder
}
local cackletongueValuePerMalice = 1

--A repositioning shift has to improve the creature's square by this much.
local repositionMinimumGain = 0.25

--Bloodpool: +5 damage for gnolls starting their turn in the pool, against
--what the exploded minion was still worth.
local bloodpoolRadius = 3
local bloodpoolValue = {nonMinion = 3, minion = 1.5}
local bloodpoolMinionWorth = 3
local bloodpoolMinimumGain = 6

--Malice kept back after Iron Jaws, so a Cackletongue chain can still open.
local ironJawsMaliceReserve = 3

--Spoken lines, kept together so they are easy to revise after playtesting.
local speech = {
    cackletongue = {"Hee hee hee!", "Laugh with me, pack!", "HAHAHAHA!"},
    cascade = {"Heh-heh-heh!", "Ha ha!", "Hyeh hyeh hyeh!"},
    callHyenas = {"Up, little ones! Feed!", "Rise and eat!"},
    callUpFromTheAbyss = {"Up from the Abyss, my hungry ones!", "The pit is hungry. Feed it!"},
    edacity = {"Consume them completely!", "Edacity! Eat!"},
    deepestWounds = {"Your wounds will never close.", "Bleed for the pack."},
    bloodpool = {"Bathe in it, pack!", "Blood for the hunt!"},
    echoesOfLaughter = {"Hear us laugh!", "Hee hee hee hee hee!"},
    ironJaws = {"Mind your step.", "Snap!"},
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

--Matches by keyword and by stat block, so gnolls from other content count too.
local function IsGnoll(token)
    return LiveCreature(token) and (HasKeyword(token, "Gnoll") or gnollMonsterSet[MonsterType(token)] == true)
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

local function HasBehavior(ability, typeName)
    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        if behavior.typeName == typeName then
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

local function IsWinded(token)
    return token.properties:CurrentHitpoints() <= MaxStamina(token)/2
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

--The Director's gnolls fighting alongside this one, itself included.
local function GnollAllies(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if IsGnoll(other) and other:IsFriend(token) and InCombat(other) and not other.playerControlled then
            result[#result+1] = other
        end
    end
    return result
end

local function CanSee(token, target)
    return token:GetLineOfSight(target, token.properties:GetPierceWalls()) > 0
end

local function NearestDistance(loc, enemies)
    local nearest = math.huge
    for _,enemy in ipairs(enemies) do
        nearest = math.min(nearest, enemy:Distance(loc))
    end
    return nearest
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

--A size 1 square no creature stands on.
local function SquareIsFree(loc, reserved)
    if loc == nil or not loc.valid or not loc.isOnMap then
        return false
    end
    if reserved ~= nil and reserved[LocKey(loc)] then
        return false
    end
    for _,other in ipairs(dmhub.GetTokensAtLoc(loc) or {}) do
        if other.valid and not other.isObject then
            return false
        end
    end
    return true
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

--The squares touching a creature's footprint.
local function SquaresAround(token)
    local result = {}
    local seen = {}
    for _,loc in ipairs(token.locsOccupying) do
        seen[LocKey(loc)] = true
    end
    for _,loc in ipairs(token.locsOccupying) do
        for dx=-1,1 do
            for dy=-1,1 do
                local candidate = OffsetLoc(loc, dx, dy)
                if candidate.valid and not seen[LocKey(candidate)] then
                    seen[LocKey(candidate)] = true
                    result[#result+1] = candidate
                end
            end
        end
    end
    return result
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

local function MaliceInCost(cost)
    local result = 0
    for _,detail in ipairs(cost.details or {}) do
        if detail.cost == CharacterResource.maliceResourceId then
            result = result + (tonumber(detail.quantity) or 0)
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Target preferences and strikes.
--------------------------------------------------------------------------------

--The house default: a slight lean toward the enemy with the most Stamina.
local function DefaultTargetScore(target, edges)
    if target.isObject or target.properties == nil then
        return 0.1 + (edges or 0)*0.1
    end
    return 1 + (edges or 0)*0.1 + MonsterAI.TargetStaminaBias(target)
end

--Dark Longbow gains an edge against any target not at full Stamina.
local function WoundedEdgeTargetScore(target, edges)
    local score = DefaultTargetScore(target, edges)
    if not target.isObject and target.properties ~= nil
        and target.properties:CurrentHitpoints() < MaxStamina(target) then
        score = score + 0.1
    end
    return score
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

--The best enemies for a strike the creature makes where it stands (a granted
--free strike, a death-triggered strike): up to the ability's target count.
local function ImmediateStrikeTargets(token, ability, symbols)
    local range = ability:GetRange(token.properties, symbols)
    local candidates = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        if MonsterAI.TargetDistance(ability:GetRangeSource(token), enemy) <= range
            and ability:TargetPassesFilter(token, enemy, symbols or {}) and CanSee(token, enemy) then
            candidates[#candidates+1] = enemy
        end
    end
    table.sort(candidates, function(a, b)
        return DefaultTargetScore(a, 0) > DefaultTargetScore(b, 0)
    end)
    local result = {}
    for i=1,math.min(#candidates, ability:GetNumTargets(token)) do
        result[#result+1] = {token = candidates[i]}
    end
    return result
end

--Reach of the creature's free strikes: 1 for melee only, more for ranged.
local function FreeStrikeReach(token, meleeOnly)
    local reach = 0
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == "Melee Free Strike"
            or (ability.name == "Ranged Free Strike" and not meleeOnly) then
            reach = math.max(reach, ability:GetRange(token.properties))
        end
    end
    return reach
end

--True when the creature could free strike an enemy where it stands.
local function CanFreeStrikeNow(token, enemies)
    local reach = FreeStrikeReach(token, false)
    for _,enemy in ipairs(enemies) do
        if MonsterAI.TargetDistance(token, enemy) <= reach and CanSee(token, enemy) then
            return true
        end
    end
    return false
end

--How the creature fights: its signature's reach, and whether it is melee.
local function StrikeProfile(token)
    local signature = SignatureAbility(token)
    if signature == nil then
        return {melee = true, range = 1}
    end
    local melee = signature:HasKeyword("Melee") and not signature:HasKeyword("Ranged")
    return {melee = melee, range = math.max(1, signature:GetRange(token.properties))}
end

--How good a square is for this creature's next attack. Melee gnolls want an
--enemy in reach; ranged ones want an enemy in range and nobody adjacent.
local function SquareUtility(loc, profile, enemies)
    local nearest = NearestDistance(loc, enemies)
    local adjacent = AdjacentEnemiesAt(enemies, loc)
    local inReach = nearest <= profile.range
    if profile.melee then
        return cond(inReach, 2, 0) + math.min(adjacent, 2)*0.15 - math.min(nearest, 20)*0.05
    end
    return cond(inReach, 2, 0) - adjacent*1.2 - math.min(nearest, 20)*0.01
end

--True when a ranged creature standing at loc could see an enemy in range.
local function SeesEnemyFrom(ai, token, loc, range, enemies)
    local found = false
    ai:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        for _,enemy in ipairs(enemies) do
            if MonsterAI.TargetDistance(token, enemy) <= range and CanSee(token, enemy) then
                found = true
                return
            end
        end
    end)
    return found
end

--Where a granted move or shift should take the creature to set up its next
--attack, or nil when nowhere within movement is clearly better.
local function RepositionPlan(ai, token, movement, flags, reserved)
    local enemies = HostileCreatures(token)
    if #enemies == 0 or movement <= 0 then
        return nil
    end
    local profile = StrikeProfile(token)
    local current = SquareUtility(token.loc, profile, enemies)
    local candidates = {}
    for _,info in pairs(token:CalculatePathfindingArea(movement*10, flags or {})) do
        local loc = info.loc
        if loc ~= nil and LocKey(loc) ~= LocKey(token.loc) and LandingIsFree(token, loc, reserved) then
            local utility = SquareUtility(loc, profile, enemies) - (info.cost or 0)*0.002
            if utility > current + repositionMinimumGain then
                candidates[#candidates+1] = {loc = loc, utility = utility}
            end
        end
    end
    table.sort(candidates, function(a, b) return a.utility > b.utility end)
    for i=1,math.min(8, #candidates) do
        local candidate = candidates[i]
        if profile.melee or SeesEnemyFrom(ai, token, candidate.loc, profile.range, enemies) then
            return candidate
        end
    end
    return nil
end

--The square within movement from which the creature can make a free strike
--(melee unless meleeOnly is false), the cheapest among the best targets.
--Returns {loc = nil} when it can already strike where it stands, nil when no
--square works.
local function FreeStrikeApproach(ai, token, movement, meleeOnly, reserved)
    local enemies = HostileCreatures(token)
    if #enemies == 0 then
        return nil
    end
    local reach = FreeStrikeReach(token, meleeOnly)
    if reach <= 0 then
        return nil
    end
    for _,enemy in ipairs(enemies) do
        if MonsterAI.TargetDistance(token, enemy) <= reach and CanSee(token, enemy) then
            return {loc = nil, target = enemy}
        end
    end
    if movement <= 0 then
        return nil
    end
    local candidates = {}
    for _,info in pairs(token:CalculatePathfindingArea(movement*10, {})) do
        local loc = info.loc
        if loc ~= nil and LandingIsFree(token, loc, reserved) then
            for _,enemy in ipairs(enemies) do
                if enemy:Distance(loc) <= reach then
                    candidates[#candidates+1] = {
                        loc = loc,
                        target = enemy,
                        utility = DefaultTargetScore(enemy, 0) - (info.cost or 0)*0.002,
                    }
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.utility > b.utility end)
    for i=1,math.min(10, #candidates) do
        local candidate = candidates[i]
        local visible = false
        ai:ExecuteWithTheoreticalMovementLoc(token, candidate.loc, function()
            visible = CanSee(token, candidate.target)
        end)
        if visible then
            return candidate
        end
    end
    return nil
end

--Squares claimed by the moves of one multi-creature effect (a Marauder's
--Cackletongue shifting every ally around it), so two allies never pick the
--same square. Forgotten once the effect has gone quiet.
local g_moveReservations = {squares = {}, time = 0}

local function MoveReservations()
    if dmhub.Time() - g_moveReservations.time > 5 then
        g_moveReservations.squares = {}
    end
    g_moveReservations.time = dmhub.Time()
    return g_moveReservations.squares
end

--Creatures whose granted move is followed by any free strike, melee or
--ranged (Edacity), rather than a melee one (Death Frenzy, Death Rampage).
local g_anyFreeStrike = {}

local function ShowMoveArrow(token, loc)
    token:MarkMovementArrow(loc, {straightline = false, ignorecreatures = false})
    MonsterAI.Sleep(movementPause)
    token:ClearMovementArrow()
end

--Ranged gnolls would otherwise spend a spare maneuver walking into melee for
--the generic Knockback, Grab or Aid Attack. Off by default for them; the
--Monster AI panel can still turn them back on.
local rangedGnolls = {"Gnoll Abyssal Archer", "Gnoll Abyssal Summoner", "Gnoll Cackler"}
for _,monsterType in ipairs(rangedGnolls) do
    for _,moveid in ipairs({"Knockback", "Grab", "Aid Attack"}) do
        MonsterAI:SetMoveEnabledForMonster(monsterType, moveid, false)
    end
end

--Once a ranged gnoll has attacked, nothing else it can do scores, and the
--framework's fallback then walks it toward the nearest enemy -- into melee.
--Holding scores just above nothing whenever an enemy is already in its
--signature's range from where it stands, which keeps it there instead.
MonsterAI:RegisterMove{
    id = "Gnoll: Hold Range",
    category = "Maneuvers",
    monsters = rangedGnolls,
    abilities = {},
    maxScore = 0.01,
    description = "A ranged gnoll with an enemy in range stays where it is instead of advancing into melee once it has nothing left to do.",
    score = function(self, ai, token)
        local profile = StrikeProfile(token)
        if profile.melee then
            return nil, "not a ranged gnoll"
        end
        for _,enemy in ipairs(HostileCreatures(token)) do
            if MonsterAI.TargetDistance(token, enemy) <= profile.range and CanSee(token, enemy) then
                return {score = 0.01}
            end
        end
        return nil, "no enemy in range from here; advancing is fine"
    end,
    execute = function(self, ai, token, scoringInfo)
    end,
}

--------------------------------------------------------------------------------
-- Cackletongue.
--------------------------------------------------------------------------------

local function IsCackletongueAbility(ability)
    return ability ~= nil and type(ability.name) == "string"
        and string.find(ability.name, "'s Cackletongue$") ~= nil
end

local function CackletongueOf(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if IsCackletongueAbility(ability) then
            return ability
        end
    end
end

local function UsedCackletongue(token)
    return HasOngoingEffect(token, usedCackletongueEffectId)
end

--The creatures a Cackletongue would affect from where the gnoll stands.
--Bursts reach through walls the way the cast does; single targets need sight.
local function CreaturesCovered(token, ability)
    local range = ability:GetRange(token.properties)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and InCombat(other)
            and MonsterAI.TargetDistance(token, other) <= range
            and ability:TargetPassesFilter(token, other, {}) then
            if ability.targetType ~= "target" or other.charid == token.charid or CanSee(token, other) then
                result[#result+1] = other
            end
        end
    end
    return result
end

--True when the creature is close enough to an enemy to strike this turn or
--next, so a bonus to its next strike will be used.
local function HasStrikeAhead(token, enemies)
    local speed = token.properties:CurrentMovementSpeed() or 0
    local profile = StrikeProfile(token)
    return NearestDistance(token.loc, enemies) <= speed*2 + profile.range
end

--True when a free shift would put the creature somewhere clearly better:
--into reach for a melee gnoll, out of melee or into range for a ranged one.
local function WantsToShift(token, enemies)
    local speed = token.properties:CurrentMovementSpeed() or 0
    local profile = StrikeProfile(token)
    local nearest = NearestDistance(token.loc, enemies)
    if profile.melee then
        return nearest > profile.range and nearest <= speed + profile.range
    end
    return AdjacentEnemiesAt(enemies, token.loc) > 0
        or (nearest > profile.range and nearest <= speed + profile.range)
end

--What using this gnoll's Cackletongue now is worth, and who it would aim at.
--castable is false for a targeted Cackletongue with nobody to target.
local function CackletonguePlan(token, ability, enemies)
    local name = ability.name
    local covered = CreaturesCovered(token, ability)
    local plan = {value = 0, castable = true, targets = nil}

    if name == "Archer's Cackletongue" or name == "Carnage's Cackletongue" then
        local weights = cond(name == "Archer's Cackletongue", cackletongueValues.edge, cackletongueValues.extraDamage)
        for _,other in ipairs(covered) do
            if other:IsFriend(token) and HasStrikeAhead(other, enemies) then
                plan.value = plan.value + cond(IsMinion(other), weights.minion, weights.nonMinion)
            end
        end
    elseif name == "Marauder's Cackletongue" then
        for _,other in ipairs(covered) do
            if other:IsFriend(token) and WantsToShift(other, enemies) then
                plan.value = plan.value + cackletongueValues.shift
            end
        end
    elseif name == "Bonesplitter's Cackletongue" then
        --Up to three of the bonesplitter and its allies make a free strike;
        --pick those who have an enemy to hit, non-minions first.
        local strikers = {}
        for _,other in ipairs(covered) do
            if other:IsFriend(token) and CanFreeStrikeNow(other, enemies) then
                strikers[#strikers+1] = other
            end
        end
        table.sort(strikers, function(a, b)
            return cond(IsMinion(a), 1, 0) < cond(IsMinion(b), 1, 0)
        end)
        plan.targets = {}
        for i=1,math.min(#strikers, ability:GetNumTargets(token)) do
            plan.targets[#plan.targets+1] = {token = strikers[i]}
        end
        plan.value = #plan.targets*cackletongueValues.freeStrike
        if #plan.targets == 0 then
            --Still passes the chain on; the bonesplitter just strikes no one.
            plan.targets = {{token = token}}
        end
    elseif name == "Cackler's Cackletongue" then
        for _,other in ipairs(covered) do
            if not other:IsFriend(token) then
                plan.value = plan.value + cackletongueValues.frightened
            end
        end
    elseif name == "Summoner's Cackletongue" then
        --The abyssal hyena nearest the enemy becomes a marauder.
        local best = nil
        local bestDistance = nil
        for _,other in ipairs(covered) do
            local distance = NearestDistance(other.loc, enemies)
            if bestDistance == nil or distance < bestDistance then
                best = other
                bestDistance = distance
            end
        end
        if best == nil then
            plan.castable = false
        else
            plan.targets = {{token = best}}
            plan.value = cackletongueValues.transform
        end
    else
        plan.value = #covered
    end

    return plan
end

--What the rest of the chain is worth: every gnoll the Cackletongue would
--reach that has not used theirs this round uses theirs for free, and each of
--those reaches further allies in turn. Positions are taken as they stand.
local function CascadeValue(starter, enemies)
    local allies = GnollAllies(starter)
    local visited = {[starter.charid] = true}
    local frontier = {starter}
    local total = 0
    local count = 0
    while #frontier > 0 do
        local current = table.remove(frontier, 1)
        local currentAbility = CackletongueOf(current)
        local reach = currentAbility ~= nil and currentAbility:GetRange(current.properties) or 0
        for _,ally in ipairs(allies) do
            if not visited[ally.charid] and MonsterAI.TargetDistance(current, ally) <= reach then
                local ability = CackletongueOf(ally)
                if ability ~= nil and not UsedCackletongue(ally) then
                    visited[ally.charid] = true
                    local plan = CackletonguePlan(ally, ability, enemies)
                    if plan.castable then
                        total = total + plan.value
                        count = count + 1
                        frontier[#frontier+1] = ally
                    end
                end
            end
        end
    end
    return total, count
end

local function PendingCackletongueTrigger(token)
    for _,trigger in pairs(token.properties:GetAvailableTriggers() or {}) do
        if not trigger.triggered and not trigger.dismissed and trigger.abilityName == "Cackletongue" then
            return trigger
        end
    end
    return nil
end

--Answers the Cackletongue prompts a chain offers to the band, one after
--another, until no new one has turned up for a moment. Run on the AI's own
--turn right after a Cackletongue, so the chain resolves before the next
--action instead of after the turn ends. Each prompt is answered by its own
--responder, so the acting monster's turn state is left alone.
local function ResolveCackletongueCascade()
    local deadline = dmhub.Time() + cascadeTimeoutSeconds
    local quietSince = dmhub.Time()
    local answered = {}
    while dmhub.Time() < deadline and not mod.unloaded do
        local found = false
        for _,token in ipairs(dmhub.allTokens) do
            if IsGnoll(token) and not token.playerControlled then
                local trigger = PendingCackletongueTrigger(token)
                if trigger ~= nil then
                    local key = string.format("%s:%s", token.charid, tostring(trigger.id))
                    if not answered[key] then
                        answered[key] = true
                        found = true
                        local responder = MonsterAI.new{token = token}
                        responder:HandleAvailableTrigger(token, trigger)
                    end
                end
            end
        end
        if found then
            quietSince = dmhub.Time()
        elseif dmhub.Time() - quietSince >= cascadeSettleSeconds then
            return
        end
        coroutine.yield(0.1)
    end
end

--Who to aim a Cackletongue at when casting it now: nil lets a burst pick its
--own targets; an empty list means there is nobody to aim it at.
local function CackletongueCastTargets(token, ability, plan)
    if ability.targetType ~= "target" then
        local result = {}
        for _,other in ipairs(CreaturesCovered(token, ability)) do
            result[#result+1] = {token = other}
        end
        return result
    end
    return plan.targets or {}
end

for monsterType,abilityName in pairs(cackletongueAbilities) do
    MonsterAI:RegisterMove{
        id = string.format("%s: %s", monsterType, abilityName),
        category = "Maneuvers",
        monsters = {monsterType},
        abilities = {abilityName},
        description = string.format("Pay for %s to open a Cackletongue chain when its own effect plus every free Cackletongue it sets off among nearby gnolls is worth the Malice. Goes before the main action.", abilityName),
        score = function(self, ai, token, ability)
            if UsedCackletongue(token) then
                return nil, "already used a Cackletongue this round"
            end
            local enemies = HostileCreatures(token)
            if #enemies == 0 then
                return nil, "no enemies"
            end
            local plan = CackletonguePlan(token, ability, enemies)
            if not plan.castable then
                return nil, "nobody to aim it at"
            end
            local cascade, chained = CascadeValue(token, enemies)
            local total = plan.value + cascade
            local malice = MaliceInCost(ability:GetCost(token))
            if total < malice*cackletongueValuePerMalice or total <= 0 then
                return nil, string.format("worth %.1f (%d allies chained) for %d Malice", total, chained, malice)
            end
            return {
                score = 1.2 + math.min(0.6, total*0.04),
                value = total,
                chained = chained,
                targets = plan.targets,
            }
        end,
        execute = function(self, ai, token, scoringInfo, ability)
            Speak(ai, token, "cackletongue")
            local targets = nil
            if ability.targetType == "target" then
                targets = scoringInfo.targets
            end
            ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
            ResolveCackletongueCascade()
        end,
    }
end

MonsterAI:RegisterTrigger{
    id = "Gnoll: Cackletongue",
    monsters = cackletongueMonsters,
    abilities = {"Cackletongue"},
    description = "Use a free Cackletongue offered by an ally's whenever it, or the rest of the chain it passes on, helps the band.",
    handler = function(ai, token, triggerInfo)
        local ability = CackletongueOf(token)
        if ability == nil or UsedCackletongue(token) then
            return {dismiss = true}
        end
        local enemies = HostileCreatures(token)
        local plan = CackletonguePlan(token, ability, enemies)
        if not plan.castable then
            return {dismiss = true}
        end
        local cascade = CascadeValue(token, enemies)
        if plan.value + cascade <= 0 then
            return {dismiss = true}
        end
        return {activate = true}
    end,
}

--"Use Cackletongue" comes in two shapes. Accepting the Cackletongue prompt
--casts one that offers the gnoll a free copy of its own Cackletongue: choose
--that copy and its targets. The Summoner's, Cackler's and Bonesplitter's
--Cackletongues also cast an area one to pass the chain on: it fires the
--prompt at the allies around the gnoll.
local function UseCackletonguePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    if HasBehavior(abilityClone, "ActivatedAbilityAugmentedAbilityBehavior") then
        local chosen = nil
        for _,synth in ipairs(abilityClone:SynthesizeAbilities(casterToken.properties) or {}) do
            if IsCackletongueAbility(synth) then
                chosen = synth
                break
            end
        end
        if chosen == nil then
            return {targets = {}}
        end
        local plan = CackletonguePlan(casterToken, chosen, HostileCreatures(casterToken))
        if not plan.castable then
            return {targets = {}}
        end
        Speak(ai, casterToken, "cascade")
        return {
            abilityOverride = chosen,
            targets = CackletongueCastTargets(casterToken, chosen, plan),
        }
    end
    local targets = {}
    for _,other in ipairs(CreaturesCovered(casterToken, abilityClone)) do
        targets[#targets+1] = {token = other}
    end
    return {targets = targets}
end

--Marauder's Cackletongue: each target shifts up to their speed.
local function MarauderShiftPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    local range = abilityClone:GetRange(casterToken.properties, symbols)
    local reserved = MoveReservations()
    local plan = RepositionPlan(ai, casterToken, range, {"shift"}, reserved)
    if plan == nil then
        return {targets = {}}
    end
    ReserveLanding(casterToken, plan.loc, reserved)
    ShowMoveArrow(casterToken, plan.loc)
    return {targets = {{loc = plan.loc}}}
end

MonsterAI:RegisterPrompt{
    id = "Gnoll Marauder: Cackletongue Shift",
    prompts = {"Gnoll Marauder:Shift"},
    handler = MarauderShiftPrompt,
}

--------------------------------------------------------------------------------
-- Granted moves and free strikes.
--------------------------------------------------------------------------------

--A strike a gnoll forces an enemy to make (Moment of Brutality): the enemy
--strikes one of its own allies, the Cackler's choice. The forced strike is
--offered as a chooser of the enemy's free strikes or signature abilities.
local function ForcedStrikePrompt(ai, invokerToken, victim, abilityClone, symbols)
    local candidates = abilityClone:SynthesizeAbilities(victim.properties) or {}
    if #candidates == 0 and abilityClone.targetType == "target" then
        candidates = {abilityClone}
    end
    local best = nil
    for _,ability in ipairs(candidates) do
        if ability.targetType == "target" then
            local range = ability:GetRange(victim.properties)
            local picks = {}
            for _,other in ipairs(dmhub.allTokens) do
                if LiveCreature(other) and InCombat(other) and other.charid ~= victim.charid
                    and not other:IsFriend(invokerToken)
                    and MonsterAI.TargetDistance(victim, other) <= range
                    and CanSee(victim, other)
                    and ability:TargetPassesFilter(victim, other, symbols or {}) then
                    picks[#picks+1] = other
                end
            end
            table.sort(picks, function(a, b)
                return DefaultTargetScore(a, 0) > DefaultTargetScore(b, 0)
            end)
            table.resize_array(picks, ability:GetNumTargets(victim))
            if #picks > 0 and (best == nil or #picks > #best.picks) then
                best = {ability = ability, picks = picks}
            end
        end
    end
    if best == nil then
        return {targets = {}}
    end
    local targets = {}
    for _,pick in ipairs(best.picks) do
        targets[#targets+1] = {token = pick}
    end
    return {abilityOverride = best.ability, targets = targets}
end

--Free strikes the band grants: Bonesplitter's Cackletongue, Shrapnel Whip and
--Moment of Brutality on an ally, Death Frenzy, Edacity, Death Snap. A
--chooser of the striker's own free strikes goes to the shared Free Strike
--handler; a concrete strike (Death Rampage's two-creature free strike, the
--archer's ranged free strike) picks its enemies directly.
local function GnollFreeStrikePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled or not casterToken:IsFriend(invokerToken) then
        return ForcedStrikePrompt(ai, invokerToken, casterToken, abilityClone, symbols)
    end
    if abilityClone.targetType == "target" then
        return {targets = ImmediateStrikeTargets(casterToken, abilityClone, symbols)}
    end
    local generic = MonsterAI.prompts["Free Strike"]
    local result = nil
    if generic ~= nil then
        result = generic.handler(ai, invokerToken, casterToken, abilityClone, symbols, options)
    end
    return result or {targets = {}}
end

--The "move up to your speed" half of Death Frenzy, Death Rampage and Edacity
--(and Death Circle on its own). Gnolls with a free strike to follow move in
--next to an enemy; minions move to where their signature will reach.
local function MoveSpeedPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    local range = abilityClone:GetRange(casterToken.properties, symbols)
    local reserved = MoveReservations()
    local loc = nil
    if IsMinion(casterToken) then
        local plan = RepositionPlan(ai, casterToken, range, {}, reserved)
        loc = plan ~= nil and plan.loc or nil
    else
        local meleeOnly = not g_anyFreeStrike[casterToken.charid]
        local plan = FreeStrikeApproach(ai, casterToken, range, meleeOnly, reserved)
        loc = plan ~= nil and plan.loc or nil
    end
    if loc == nil then
        return {targets = {}}
    end
    ReserveLanding(casterToken, loc, reserved)
    ShowMoveArrow(casterToken, loc)
    return {targets = {{loc = loc}}}
end

--A wrapper the creature casts on itself (move, then free strike).
local function SelfTargetPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    return {targets = {{token = casterToken}}}
end

--Bloodpool's pool and the shared free strike wrapper share a name. The pool
--is cast by the exploding minion as a burst, and every creature it targets
--gets its own pool, so aim it at the minion alone: one pool where it burst.
local function InvokedAbilityPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if HasBehavior(abilityClone, "ActivatedAbilityAuraBehavior") then
        return {targets = {{token = casterToken}}}
    end
    local generic = MonsterAI.prompts["Invoked Ability"]
    if generic ~= nil then
        return generic.handler(ai, invokerToken, casterToken, abilityClone, symbols, options)
    end
    return nil
end

local function ConcreteStrikePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    return {targets = ImmediateStrikeTargets(casterToken, abilityClone, symbols)}
end

--Prompt names are qualified by the invoking gnoll's stat block so other bands'
--abilities with the same names are untouched.
local function QualifiedPrompts(names)
    local result = {}
    for _,monsterType in ipairs(gnollMonsters) do
        for _,name in ipairs(names) do
            result[#result+1] = monsterType .. ":" .. name
        end
    end
    return result
end

MonsterAI:RegisterPrompt{
    id = "Gnoll: Use Cackletongue",
    prompts = QualifiedPrompts({"Use Cackletongue"}),
    handler = UseCackletonguePrompt,
}

MonsterAI:RegisterPrompt{
    id = "Gnoll: Free Strike",
    prompts = QualifiedPrompts({"Make Free Strike", "Make Melee Free Strike", "Free Strike M<2 Prone", "Free Strike", "Signature Ability"}),
    handler = GnollFreeStrikePrompt,
}

MonsterAI:RegisterPrompt{
    id = "Gnoll: Strike Where It Stands",
    prompts = QualifiedPrompts({"Ranged Free Strike", "Shrapnel Whip"}),
    handler = ConcreteStrikePrompt,
}

MonsterAI:RegisterPrompt{
    id = "Gnoll: Move Speed",
    prompts = QualifiedPrompts({"Move Speed"}),
    handler = MoveSpeedPrompt,
}

MonsterAI:RegisterPrompt{
    id = "Gnoll: Move and Free Strike",
    prompts = QualifiedPrompts({"Move Speed and Make Melee Free Strike", "Move Speed & Make Free Strike"}),
    handler = SelfTargetPrompt,
}

MonsterAI:RegisterPrompt{
    id = "Gnoll: Invoked Ability",
    prompts = QualifiedPrompts({"Invoked Ability"}),
    handler = InvokedAbilityPrompt,
}

--------------------------------------------------------------------------------
-- Death triggers.
--------------------------------------------------------------------------------

MonsterAI:RegisterTrigger{
    id = "Gnoll: Death Circle",
    monsters = {"Gnoll Chainflail", "Gnoll Mage Mauler", "Gnoll Wildling"},
    abilities = {"Death Circle"},
    description = "When a nearby gnoll leader falls, move to where the minion's signature reaches; stay put if nowhere is better.",
    handler = function(ai, token, triggerInfo)
        local speed = token.properties:CurrentMovementSpeed() or 0
        if RepositionPlan(ai, token, speed, {}, nil) == nil then
            return {dismiss = true}
        end
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Gnoll Abyssal Archer: Distant Death Frenzy",
    monsters = {"Gnoll Abyssal Archer"},
    abilities = {"Distant Death Frenzy"},
    description = "Take the ranged free strike whenever an enemy is in range.",
    handler = function(ai, token, triggerInfo)
        if not CanFreeStrikeNow(token, HostileCreatures(token)) then
            return {dismiss = true}
        end
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Gnoll: Death Frenzy",
    monsters = {"Gnoll Abyssal Summoner", "Gnoll Cackler", "Gnoll Bonesplitter", "Gnoll Marauder"},
    abilities = {"Death Frenzy"},
    description = "When a nearby gnoll falls, run in for a melee free strike if an enemy is within speed.",
    handler = function(ai, token, triggerInfo)
        local speed = token.properties:CurrentMovementSpeed() or 0
        if FreeStrikeApproach(ai, token, speed, true, nil) == nil then
            return {dismiss = true}
        end
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Gnoll Carnage: Death Rampage",
    monsters = {"Gnoll Carnage"},
    abilities = {"Death Rampage"},
    description = "When a nearby gnoll falls, move in and free strike two enemies if two are within reach of one square, otherwise Shrapnel Whip one.",
    handler = function(ai, token, triggerInfo)
        local speed = token.properties:CurrentMovementSpeed() or 0
        local approach = FreeStrikeApproach(ai, token, speed, true, nil)
        if approach == nil then
            return {dismiss = true}
        end
        local loc = approach.loc or token.loc
        if AdjacentEnemiesAt(HostileCreatures(token), loc) >= 2 then
            return {activate = true, mode = 1}
        end
        return {activate = true, mode = 2}
    end,
}

--The enemy each tusker is charging for Vengeful Tusker, by tusker charid.
local g_vengefulTargets = {}

MonsterAI:RegisterTrigger{
    id = "Tusker Demon: Vengeful Tusker",
    monsters = {"Tusker Demon"},
    abilities = {"Vengeful Tusker"},
    description = "Always charge an enemy who hurt the tusker.",
    handler = function(ai, token, triggerInfo)
        g_vengefulTargets[token.charid] = nil
        for _,charid in ipairs(triggerInfo.targets or {}) do
            local attacker = dmhub.GetTokenById(charid)
            if attacker ~= nil and LiveCreature(attacker) and not attacker:IsFriend(token) then
                g_vengefulTargets[token.charid] = attacker.charid
                break
            end
        end
        return {activate = true}
    end,
}

--Vengeful Tusker's Charge: a straight run to where Gore reaches the enemy
--who hurt the tusker (or, failing that, the nearest enemy it can reach).
MonsterAI:RegisterPrompt{
    id = "Tusker Demon: Vengeful Charge",
    prompts = {"Tusker Demon:Charge"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local gore = FindAbility(casterToken, "Gore")
        local reach = gore ~= nil and gore:GetRange(casterToken.properties) or 1
        local speed = casterToken.properties:CurrentMovementSpeed() or 0
        local mover = ai:GetMovementToken(casterToken)
        local preferred = g_vengefulTargets[casterToken.charid]
        local enemies = HostileCreatures(casterToken)
        table.sort(enemies, function(a, b)
            if (a.charid == preferred) ~= (b.charid == preferred) then
                return a.charid == preferred
            end
            return MonsterAI.TargetDistance(casterToken, a) < MonsterAI.TargetDistance(casterToken, b)
        end)
        for _,enemy in ipairs(enemies) do
            if MonsterAI.TargetDistance(casterToken, enemy) <= speed + reach then
                local probe = ai:ChargeProbe(mover, enemy, speed, reach)
                if probe ~= nil and probe.chargeDist > 0 then
                    g_vengefulTargets[casterToken.charid] = enemy.charid
                    return {targets = {{loc = probe.dest}}}
                end
            end
        end
        return {targets = {}}
    end,
}

--The strike at the end of the charge: Gore, the charged enemy first.
MonsterAI:RegisterPrompt{
    id = "Tusker Demon: Attack when Charging",
    prompts = {"Tusker Demon:Attack when Charging"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local chosen = nil
        for _,synth in ipairs(abilityClone:SynthesizeAbilities(casterToken.properties) or {}) do
            if synth.name == "Gore" then
                chosen = synth
            end
        end
        if chosen == nil then
            local generic = MonsterAI.prompts["Free Strike"]
            return generic ~= nil and generic.handler(ai, invokerToken, casterToken, abilityClone, symbols, options) or nil
        end
        local targets = ImmediateStrikeTargets(casterToken, chosen, symbols)
        local preferred = g_vengefulTargets[casterToken.charid]
        table.sort(targets, function(a, b)
            return a.token.charid == preferred and b.token.charid ~= preferred
        end)
        g_vengefulTargets[casterToken.charid] = nil
        if #targets == 0 then
            return {targets = {}}
        end
        return {abilityOverride = chosen, targets = targets}
    end,
}

--------------------------------------------------------------------------------
-- Signature strikes and other moves.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Gnoll Abyssal Archer: Dark Longbow",
    category = "Main Actions",
    monsters = {"Gnoll Abyssal Archer"},
    abilities = {"Dark Longbow"},
    description = "Shoot from range, preferring enemies who are not at full Stamina (the longbow gains an edge against them).",
    score = StrikeScore(1, WoundedEdgeTargetScore),
    execute = StrikeExecute(WoundedEdgeTargetScore),
}

MonsterAI:RegisterMove{
    id = "Gnoll Abyssal Summoner: Flame Wad",
    category = "Main Actions",
    monsters = {"Gnoll Abyssal Summoner"},
    abilities = {"Flame Wad"},
    description = "Signature ranged strike.",
    score = StrikeScore(1, DefaultTargetScore),
    execute = StrikeExecute(DefaultTargetScore),
}

MonsterAI:RegisterMove{
    id = "Gnoll Marauder: Fury Flail",
    category = "Main Actions",
    monsters = {"Gnoll Marauder"},
    abilities = {"Fury Flail"},
    description = "Signature melee strike.",
    score = StrikeScore(1, DefaultTargetScore),
    execute = StrikeExecute(DefaultTargetScore),
}

MonsterAI:RegisterMove{
    id = "Tusker Demon: Gore",
    category = "Main Actions",
    monsters = {"Tusker Demon"},
    abilities = {"Gore"},
    description = "Gore two enemies, charging when that reaches them.",
    score = StrikeScore(1, DefaultTargetScore),
    execute = StrikeExecute(DefaultTargetScore),
}

--Abyssal hyenas called up beside the enemy.
local function HyenaSquares(token, range, count)
    local reserved = {}
    local result = {}
    local enemies = HostileCreatures(token)
    table.sort(enemies, function(a, b)
        return DefaultTargetScore(a, 0) > DefaultTargetScore(b, 0)
    end)
    local pierceWalls = token.properties:GetPierceWalls()
    --Round-robin around the enemies so every hero gets company.
    local rings = {}
    local cursors = {}
    for _,enemy in ipairs(enemies) do
        rings[#rings+1] = SquaresAround(enemy)
        cursors[#cursors+1] = 1
    end
    local progress = true
    while #result < count and progress do
        progress = false
        for i,ring in ipairs(rings) do
            while cursors[i] <= #ring do
                local loc = ring[cursors[i]]
                cursors[i] = cursors[i] + 1
                if SquareIsFree(loc, reserved) and token:Distance(loc) <= range
                    and token:GetLineOfSight(loc, pierceWalls) > 0 then
                    reserved[LocKey(loc)] = true
                    result[#result+1] = {loc = loc}
                    progress = true
                    break
                end
            end
            if #result >= count then
                break
            end
        end
    end
    return result
end

MonsterAI:RegisterMove{
    id = "Gnoll Abyssal Summoner: Call Abyssal Hyenas",
    category = "Maneuvers",
    monsters = {"Gnoll Abyssal Summoner"},
    abilities = {"Call Abyssal Hyenas"},
    description = "Spend 3 Malice to call up two abyssal hyenas when an enemy is in range to set on.",
    score = function(self, ai, token, ability)
        local range = ability:GetRange(token.properties)
        local enemies = HostileCreatures(token)
        if NearestDistance(token.loc, enemies) > range + 1 then
            return nil, "no enemy near enough for the hyenas"
        end
        return {score = 0.9}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        Speak(ai, token, "callHyenas")
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--Three-Tail Flail can only hit the creature the bonesplitter is grabbing,
--if any (mode 1); otherwise it is an ordinary strike (mode 2).
local function GrabbedBy(token)
    local result = {}
    local conditions = dmhub.GetTable(CharacterCondition.tableName) or {}
    pcall(function()
        token.properties:VisitConditionCasterSource(function(conditionid, targetToken)
            local condition = conditions[conditionid]
            if condition ~= nil and condition.name == "Grabbed" and LiveCreature(targetToken) then
                result[#result+1] = targetToken
            end
        end)
    end)
    return result
end

MonsterAI:RegisterMove{
    id = "Gnoll Bonesplitter: Three-Tail Flail",
    category = "Main Actions",
    monsters = {"Gnoll Bonesplitter"},
    abilities = {"Three-Tail Flail"},
    description = "Keep flailing the creature the bonesplitter has grabbed; otherwise its best melee strike.",
    score = function(self, ai, token, ability)
        local grabbed = GrabbedBy(token)
        if #grabbed > 0 then
            local held = ability:SwitchModes(1)
            for _,target in ipairs(grabbed) do
                if MonsterAI.TargetDistance(token, target) <= held:GetRange(token.properties) then
                    return {score = 1.1, mode = 1, target = target}
                end
            end
        end
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, DefaultTargetScore)
        if loc ~= nil and targetScore ~= nil and targetScore > 0 then
            return {score = 1 + math.min(0.2, math.max(0, targetScore - 1)*0.1), mode = 2, loc = loc}
        end
        return nil, "no enemy can be struck this turn"
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        if scoringInfo.mode == 1 then
            ai:ExecuteAbility(token, ability:SwitchModes(1), {{token = scoringInfo.target}},
                {sleep = abilityPause, symbols = {mode = 1}})
            return
        end
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, DefaultTargetScore)
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause, symbols = {mode = 2}})
    end,
}

--An ally gnoll that a strike can target instead of an enemy to hand it a
--free strike (Shrapnel Whip, Moment of Brutality): one in range and sight of
--loc that has an enemy within its own free strike reach.
local function BestFreeStrikeAlly(ai, token, ability, loc, exclude)
    local range = ability:GetRange(token.properties)
    local best = nil
    local bestScore = nil
    ai:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        for _,ally in ipairs(GnollAllies(token)) do
            if ally.charid ~= token.charid and (exclude == nil or not exclude[ally.charid])
                and MonsterAI.TargetDistance(token, ally) <= range and CanSee(token, ally)
                and ability:TargetPassesFilter(token, ally, {})
                and CanFreeStrikeNow(ally, HostileCreatures(ally)) then
                local score = cond(IsMinion(ally), 1, 2)
                if bestScore == nil or score > bestScore then
                    best = ally
                    bestScore = score
                end
            end
        end
    end)
    return best
end

MonsterAI:RegisterMove{
    id = "Gnoll Carnage: Shrapnel Whip",
    category = "Main Actions",
    monsters = {"Gnoll Carnage"},
    abilities = {"Shrapnel Whip"},
    description = "Whip two enemies; with only one in reach, whip an ally beside an enemy too, which then makes a free strike.",
    score = StrikeScore(1, DefaultTargetScore),
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, token.loc, DefaultTargetScore)
        if #targets > 0 and #targets < ability:GetNumTargets(token) then
            local ally = BestFreeStrikeAlly(ai, token, ability, token.loc)
            if ally ~= nil then
                targets[#targets+1] = {token = ally}
            end
        end
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Gnoll Cackler: Moment of Brutality",
    category = "Main Actions",
    monsters = {"Gnoll Cackler"},
    abilities = {"Moment of Brutality"},
    description = "Turn an enemy's own strike on their friends; with no enemy in range, target an ally beside an enemy so it makes a free strike.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, DefaultTargetScore)
        if loc ~= nil and targetScore ~= nil and targetScore > 0 then
            return {score = 1 + math.min(0.2, math.max(0, targetScore - 1)*0.1), loc = loc}
        end
        local ally = BestFreeStrikeAlly(ai, token, ability, token.loc)
        if ally ~= nil then
            return {score = 0.6, ally = ally}
        end
        return nil, "no enemy or striking ally in range"
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        if scoringInfo.ally ~= nil then
            ai:ExecuteAbility(token, ability, {{token = scoringInfo.ally}}, {sleep = abilityPause})
            return
        end
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, token.loc, DefaultTargetScore)
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Gnoll Carnage villain actions.
--------------------------------------------------------------------------------

--The data names these villain actions with a trailing space; register both
--spellings so a later data fix does not silently drop them.
local function VillainActionNames(name)
    return {name, name .. " "}
end

for _,abilityName in ipairs(VillainActionNames("Call Up from The Abyss")) do
    MonsterAI:RegisterVillainAction{
        id = "Gnoll Carnage: Call Up from the Abyss" .. cond(abilityName ~= "Call Up from The Abyss", " (data spelling)", ""),
        monsters = {"Gnoll Carnage"},
        abilities = {abilityName},
        description = "Summon four abyssal hyenas into the squares around the enemy.",
        score = function(self, ai, token, ability, context)
            local squares = HyenaSquares(token, ability:GetRange(token.properties), ability:GetNumTargets(token))
            if #squares == 0 then
                return nil, "no free square in range"
            end
            return {score = 0.85, squares = #squares}
        end,
        execute = function(self, ai, token, scoringInfo, ability, context)
            local squares = HyenaSquares(token, ability:GetRange(token.properties), ability:GetNumTargets(token))
            Speak(ai, token, "callUpFromTheAbyss")
            ai:ExecuteAbility(token, ability, squares, {sleep = abilityPause})
        end,
    }
end

--Up to three allies within 10 who can get to an enemy for a free strike. The
--carnage itself always takes part: the cast adds it as well as its targets.
local function EdacityStrikers(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local strikers = {}
    for _,ally in ipairs(GnollAllies(token)) do
        if ally.charid ~= token.charid and MonsterAI.TargetDistance(token, ally) <= range
            and ability:TargetPassesFilter(token, ally, {}) then
            local speed = ally.properties:CurrentMovementSpeed() or 0
            if FreeStrikeApproach(ai, ally, speed, false, nil) ~= nil then
                strikers[#strikers+1] = ally
            end
        end
    end
    --Non-minions first: their strikes hit hardest.
    table.sort(strikers, function(a, b)
        return cond(IsMinion(a), 1, 0) < cond(IsMinion(b), 1, 0)
    end)
    table.resize_array(strikers, ability:GetNumTargets(token))
    return strikers
end

for _,abilityName in ipairs(VillainActionNames("Edacity")) do
    MonsterAI:RegisterVillainAction{
        id = "Gnoll Carnage: Edacity" .. cond(abilityName ~= "Edacity", " (data spelling)", ""),
        monsters = {"Gnoll Carnage"},
        abilities = {abilityName},
        description = "The carnage and allies within 10 who can reach an enemy each move up to their speed and free strike.",
        score = function(self, ai, token, ability, context)
            local count = #EdacityStrikers(ai, token, ability)
            local speed = token.properties:CurrentMovementSpeed() or 0
            if FreeStrikeApproach(ai, token, speed, false, nil) ~= nil then
                count = count + 1
            end
            if count == 0 then
                return nil, "nobody can reach an enemy"
            end
            return {score = math.min(1, 0.45 + count*0.15), strikers = count}
        end,
        execute = function(self, ai, token, scoringInfo, ability, context)
            local strikers = EdacityStrikers(ai, token, ability)
            local targets = {}
            for _,striker in ipairs(strikers) do
                targets[#targets+1] = {token = striker}
            end
            local acting = {token}
            for _,striker in ipairs(strikers) do
                acting[#acting+1] = striker
            end
            for _,striker in ipairs(acting) do
                g_anyFreeStrike[striker.charid] = true
            end
            Speak(ai, token, "edacity")
            --Each striker answers its own move and free strike prompts.
            local ok, err = pcall(WithControlOf, ai, acting, function()
                ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
                ai:WaitForAbilityIdle(60)
            end)
            for _,striker in ipairs(acting) do
                g_anyFreeStrike[striker.charid] = nil
            end
            if not ok then
                error(err)
            end
        end,
    }
end

for _,abilityName in ipairs(VillainActionNames("Deepest Wounds")) do
    MonsterAI:RegisterVillainAction{
        id = "Gnoll Carnage: Deepest Wounds" .. cond(abilityName ~= "Deepest Wounds", " (data spelling)", ""),
        monsters = {"Gnoll Carnage"},
        abilities = {abilityName},
        description = "Stop winded enemies within 5 from regaining Stamina; better the more winded enemies it catches.",
        score = function(self, ai, token, ability, context)
            local range = ability:GetRange(token.properties)
            local winded = 0
            for _,enemy in ipairs(HostileCreatures(token)) do
                if MonsterAI.TargetDistance(token, enemy) <= range and IsWinded(enemy) then
                    winded = winded + 1
                end
            end
            return {score = math.min(1, 0.3 + winded*0.25), winded = winded}
        end,
        execute = function(self, ai, token, scoringInfo, ability, context)
            Speak(ai, token, "deepestWounds")
            ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        end,
    }
end

--------------------------------------------------------------------------------
-- Start-of-turn Gnoll Malice features.
--------------------------------------------------------------------------------

--Echoes of Laughter lasts the encounter. Keyed by initiative queue guid; local
--memory only, like the framework's own Malice history.
local g_echoesUsedByEncounter = {}

local function ExecuteMapAbility(ai, caster, ability, targetTokens)
    local area = dmhub.CalculateShape{
        shape = "map",
        token = caster,
    }
    local symbols = {targetArea = area}
    local targets = {}
    for _,target in ipairs(targetTokens) do
        if LiveCreature(target) then
            targets[#targets+1] = {token = target}
        end
    end
    ai:ExecuteAbility(caster, DeepCopy(ability), targets, {
        sleep = abilityPause,
        symbols = symbols,
        targetArea = area,
    })
end

MonsterAI:RegisterMaliceAbility{
    id = "Gnoll Malice: Echoes of Laughter",
    monsterGroups = gnollGroup,
    abilities = {"Echoes of Laughter"},
    description = "Spend 7 Malice on Echoes of Laughter once per encounter, early, while at least two enemies are fighting.",
    score = function(self, ai, token, ability, context)
        local queue = context.initiativeQueue
        if queue ~= nil and g_echoesUsedByEncounter[queue.guid] then
            return nil, "already used this encounter"
        end
        local enemies = {}
        for _,enemy in ipairs(context.enemyTokens or {}) do
            if LiveCreature(enemy) then
                if HasOngoingEffect(enemy, echoesOfLaughterEffectId) then
                    return nil, "the laughter is already on the map"
                end
                enemies[#enemies+1] = enemy
            end
        end
        if #enemies < 2 then
            return nil, "fewer than two enemies"
        end
        return {score = cond((context.round or 1) <= 3, 0.92, 0.75), enemies = #enemies}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,enemy in ipairs(context.enemyTokens or {}) do
            if LiveCreature(enemy) and ability:TargetPassesFilter(token, enemy, {}) then
                targets[#targets+1] = enemy
            end
        end
        Speak(ai, token, "echoesOfLaughter")
        ExecuteMapAbility(ai, token, ability, targets)
        local queue = context.initiativeQueue
        if queue ~= nil then
            g_echoesUsedByEncounter[queue.guid] = true
        end
    end,
}

--Where this encounter's Bloodpools burst, keyed by initiative queue guid. The
--pools last the encounter, so a gnoll already standing in one gains nothing
--from another. Local memory only, like the framework's own Malice history.
local g_bloodpoolsByEncounter = {}

local function InExistingBloodpool(token, pools)
    for _,loc in ipairs(pools) do
        if token:Distance(loc) <= bloodpoolRadius then
            return true
        end
    end
    return false
end

--The gnoll minion whose blood would bathe the most gnolls, against what that
--minion would still have done.
local function FindBloodpoolPlan(token, ability, context)
    local enemies = context.enemyTokens or {}
    local gnolls = GnollAllies(token)
    local queue = context.initiativeQueue
    local pools = queue ~= nil and g_bloodpoolsByEncounter[queue.guid] or {}
    local best = nil
    for _,minion in ipairs(gnolls) do
        if IsMinion(minion) and ability:TargetPassesFilter(token, minion, {}) then
            local gain = 0
            local bathed = 0
            for _,other in ipairs(gnolls) do
                if other.charid ~= minion.charid and MonsterAI.TargetDistance(minion, other) <= bloodpoolRadius
                    and not InExistingBloodpool(other, pools) then
                    gain = gain + cond(IsMinion(other), bloodpoolValue.minion, bloodpoolValue.nonMinion)
                    bathed = bathed + 1
                end
            end
            --A minion that can already reach an enemy is worth keeping.
            local worth = bloodpoolMinionWorth
            local speed = minion.properties:CurrentMovementSpeed() or 0
            if NearestDistance(minion.loc, enemies) <= speed + 1 then
                worth = worth + 2
            end
            gain = gain - worth
            if best == nil or gain > best.gain then
                best = {minion = minion, gain = gain, bathed = bathed}
            end
        end
    end
    return best
end

MonsterAI:RegisterMaliceAbility{
    id = "Gnoll Malice: Bloodpool",
    monsterGroups = gnollGroup,
    abilities = {"Bloodpool"},
    description = "Spend 5 Malice to burst a gnoll minion surrounded by other gnolls, when the extra damage they gain outweighs the minion.",
    score = function(self, ai, token, ability, context)
        local plan = FindBloodpoolPlan(token, ability, context)
        if plan == nil then
            return nil, "no gnoll minion can be targeted"
        end
        if plan.gain < bloodpoolMinimumGain then
            return nil, string.format("best pool gains only %.1f", plan.gain)
        end
        return {
            score = math.min(0.88, 0.68 + (plan.gain - bloodpoolMinimumGain)*0.02),
            minion = plan.minion,
            bathed = plan.bathed,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local minion = scoringInfo.minion
        if not LiveCreature(minion) then
            return
        end
        local burstAt = minion.loc
        Speak(ai, token, "bloodpool")
        ai:ExecuteAbility(token, ability, {{token = minion}}, {sleep = abilityPause})
        local queue = context.initiativeQueue
        if queue ~= nil then
            local pools = g_bloodpoolsByEncounter[queue.guid] or {}
            pools[#pools+1] = burstAt
            g_bloodpoolsByEncounter[queue.guid] = pools
        end
    end,
}

--Squares already holding a snare. A placed snare is kept in its caster's
--auras list with the square it covers.
local function SnaredSquares(ability)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if other.valid and other.properties ~= nil then
            for _,aura in ipairs(other.properties:try_get("auras", {})) do
                if aura:try_get("sourceAbilityId") == ability:try_get("guid") or aura:try_get("name") == ability.name then
                    local area = aura:GetArea()
                    for _,loc in ipairs(area ~= nil and area.locations or {}) do
                        result[LocKey(loc)] = true
                    end
                end
            end
        end
    end
    return result
end

--The snare square: beside the enemy the caster can best cover, on the side
--that faces the gnolls, so the enemy steps in on its way to them.
local function FindIronJawsSquare(token, ability, context)
    local range = ability:GetRange(token.properties)
    local pierceWalls = token.properties:GetPierceWalls()
    local gnolls = GnollAllies(token)
    local snared = SnaredSquares(ability)
    local best = nil
    for _,enemy in ipairs(context.enemyTokens or {}) do
        if LiveCreature(enemy) then
            for _,loc in ipairs(SquaresAround(enemy)) do
                if SquareIsFree(loc, snared) and token:Distance(loc) <= range
                    and token:GetLineOfSight(loc, pierceWalls) > 0 then
                    --Closer to the gnolls than the enemy is: on the way to them.
                    local towardGnolls = 0
                    for _,gnoll in ipairs(gnolls) do
                        if gnoll:Distance(loc) < gnoll:Distance(enemy.loc) then
                            towardGnolls = towardGnolls + 1
                        end
                    end
                    local utility = towardGnolls + DefaultTargetScore(enemy, 0)
                    if best == nil or utility > best.utility then
                        best = {loc = loc, utility = utility}
                    end
                end
            end
        end
    end
    return best
end

MonsterAI:RegisterMaliceAbility{
    id = "Gnoll Malice: Iron Jaws",
    monsterGroups = gnollGroup,
    abilities = {"Iron Jaws"},
    description = "Spend 3 Malice to snare a square beside an enemy, on its way to the gnolls, when Malice is left over for a Cackletongue chain.",
    score = function(self, ai, token, ability, context)
        local malice = context.malice or CharacterResource.GetMalice()
        if malice - MaliceInCost(ability:GetCost(token)) < ironJawsMaliceReserve then
            return nil, "keeping Malice for Cackletongue"
        end
        local square = FindIronJawsSquare(token, ability, context)
        if square == nil then
            return nil, "no free square beside an enemy in range"
        end
        return {score = 0.68, center = square.loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local center = scoringInfo.center
        local area = dmhub.CalculateShape{
            shape = "cube",
            targetPoint = token:PosAtLoc(center),
            token = token,
            range = ability:GetRange(token.properties),
            radius = ability:GetRadius(token.properties),
            checklos = false,
            altitude = center.withGroundAltitude.altitude * dmhub.unitsPerSquare,
        }
        Speak(ai, token, "ironJaws")
        ai:ExecuteAbility(token, DeepCopy(ability), {}, {
            sleep = abilityPause,
            symbols = {targetArea = area},
            targetArea = area,
        })
    end,
}
