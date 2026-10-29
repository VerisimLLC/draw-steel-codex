local mod = dmhub.GetModLoading()

--Monster AI for the echelon 1 demons: the Ensnarer, Frenzied and Pitling
--minions, the Ruinant, Torlas, Bendrak, Remasch and Muceron horde demons, the
--Chorogaunt leader (and the Lesser Demon Chorogaunt variant), and the level 1+
--Demon Malice features (Soulburn, Abyssal Evolution, Abyssal Rift).
--
--Demons are hungry, not clever, so most of this is about using each stat
--block's tools in the right order:
--  * The Torlas turns the ground to flesh (difficult terrain that hurts anyone
--    moving in it), then slides and pulls heroes through it.
--  * The Muceron and Ensnarer strike from 2-3 squares away so the pull drags
--    the hero adjacent and earns the free strike.
--  * The Remasch hits and teleports away, and pays for Grasping Shadow to do it
--    twice in a turn.
--  * The Chorogaunt slides heroes into its Agonizing Harmony burst first, and
--    uses each Harmony's free shift on the ally who gains most from it.
--Minion signature strikes are left to the shared squad logic.

local movementPause = 0.6
local stationaryPause = 0.35
local speechPause = 0.45
local abilityPause = 0.9

local demonGroup = {"Demon"}

local demonMonsters = {
    "Demon Ensnarer",
    "Demon Frenzied",
    "Demon Pitling",
    "Demon Ruinant",
    "Demon Torlas",
    "Demon Bendrak",
    "Demon Remasch",
    "Demon Muceron",
    "Demon Chorogaunt",
    "Lesser Demon Chorogaunt",
}

local demonMonsterSet = {}
for _,monsterType in ipairs(demonMonsters) do
    demonMonsterSet[monsterType] = true
end

local chorogaunts = {"Demon Chorogaunt", "Lesser Demon Chorogaunt"}

--Demons that fight from range.
local rangedDemons = {"Demon Bendrak", "Demon Torlas"}

--Malice the band keeps back when deciding whether an optional spend is worth it.
local saltWoundsMinimumTargets = 2
local tongueMinimumTargets = 2
local vanishThreatDistance = 7
--I Thrive on Pain is spent freely by a hurt chorogaunt, otherwise only when
--Malice is plentiful.
local thriveFreeMalice = 6
--End Effect costs 5 Stamina the chorogaunt cannot reduce.
local endEffectStaminaFloor = 20
--Abyssal Rift is the band's least useful Malice feature: only spent when
--Malice is piling up.
local abyssalRiftMinimumMalice = 12

--Spoken lines, kept together so they are easy to revise after playtesting.
local speech = {
    hunger = {"Hungry... so hungry...", "Your soul smells sweet.", "Feed us!"},
    floorToFlesh = {"The ground hungers!", "Sink into us!", "Flesh! Flesh!"},
    tendons = {"Come closer.", "Into the meat!"},
    tongue = {"Come here, morsel.", "Mine!"},
    saltWounds = {"Let them burn.", "Your wounds sing to me."},
    vanish = {"Gone...", "You never saw me."},
    abyssalStrike = {"From the dark!", "Behind you."},
    graspingShadow = {"The shadows take you!", "Again!"},
    harmony = {"SING WITH US!", "Hear the choir of souls!", "Scream for me!"},
    entrancing = {"Dance, little souls.", "Come into the song."},
    frighteningTones = {"Choose: your mind or your flesh.", "Tremble!"},
    bullyTheWeak = {"Weakling. Feed the strong!", "You are fodder."},
    runningCacophony = {"The song never ends!", "Cacophony!"},
    soulburn = {"Burn the souls! Burn them!", "More! MORE!"},
    evolution = {"Grow, little one. Grow!", "Become more!"},
    rift = {"The Abyss opens!", "Home calls to us."},
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

--Matches by keyword and by stat block, so demons from other content count too.
local function IsDemon(token)
    return LiveCreature(token) and (HasKeyword(token, "Demon") or demonMonsterSet[MonsterType(token)] == true)
end

local function IsChorogaunt(token)
    local monsterType = MonsterType(token)
    return monsterType == "Demon Chorogaunt" or monsterType == "Lesser Demon Chorogaunt"
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

--MaxHitpoints(), not the max_hitpoints field: on a hero that field is only
--a base value, far below the real maximum.
local function MaxStamina(token)
    return math.max(1, token.properties:MaxHitpoints())
end

local function StaminaFraction(token)
    return token.properties:CurrentHitpoints()/MaxStamina(token)
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

local function CurrentRound()
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return 0
    end
    return queue.round or 0
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

--The Director's demons fighting alongside this one, itself included.
local function DemonAllies(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if IsDemon(other) and other:IsFriend(token) and InCombat(other) and not other.playerControlled then
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

local function MaliceInCost(cost)
    local result = 0
    for _,detail in ipairs(cost.details or {}) do
        if detail.cost == CharacterResource.maliceResourceId then
            result = result + (tonumber(detail.quantity) or 0)
        end
    end
    return result
end

local function ShowMoveArrow(token, loc)
    token:MarkMovementArrow(loc, {straightline = false, ignorecreatures = false})
    MonsterAI.Sleep(movementPause)
    token:ClearMovementArrow()
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

--Runs fn (a cast that kills one of the band's own squad minions outright:
--Bully the Weak, Abyssal Evolution) while choosing the squad's owed death as
--the AI. Destroying a minion records no attacker, so the squad would
--otherwise wait for the Director to click its skull, stalling the turn.
local function WithOwnMinionDeathsResolved(ai, killer, victim, fn)
    local done = false
    dmhub.Coroutine(function()
        while not done and not mod.unloaded do
            pcall(function()
                if victim.valid and victim.properties ~= nil and IsMinion(victim) then
                    victim.properties._tmp_lastattacker = killer.properties
                end
                ai:ResolvePendingMinionDeaths(0)
            end)
            coroutine.yield(0.2)
        end
    end)
    local ok, err = ai:RunYieldingFunction(function()
        fn()
        ai:WaitForAbilityIdle(30)
    end)
    done = true
    if not ok then
        error(err)
    end
end

--The targets of a cast of abilityName this creature has under way: a prompt
--fired from inside Barbed Tongues reads who the tongue struck. For a minion
--squad's volley only this member's own pairs count.
local function TargetsOfRunningCast(caster, abilityName)
    local result = {}
    local seen = {}
    for _,info in pairs(ActivatedAbility.coroutineStorage or {}) do
        local castCaster = info.casterToken
        if info.ability ~= nil and info.ability.name == abilityName then
            local pairsList = info.options ~= nil and info.options.symbols ~= nil and info.options.symbols.targetPairs or nil
            if pairsList ~= nil then
                for _,pair in ipairs(pairsList) do
                    if pair.a == caster.charid and not seen[pair.b] then
                        local target = dmhub.GetTokenById(pair.b)
                        if target ~= nil then
                            seen[pair.b] = true
                            result[#result+1] = target
                        end
                    end
                end
            elseif castCaster ~= nil and castCaster.valid and castCaster.charid == caster.charid then
                for _,targetInfo in ipairs(info.targets or {}) do
                    local target = targetInfo.token
                    if target ~= nil and not seen[target.charid] then
                        seen[target.charid] = true
                        result[#result+1] = target
                    end
                end
            end
        end
    end
    return result
end

--{token = ...} entries for a list of tokens: the shape cast targets and the
--framework's plan log expect.
local function TokenTargets(tokens)
    local result = {}
    for _,tok in ipairs(tokens) do
        result[#result+1] = {token = tok}
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

local function StrikeExecute(scorefn, speechKey)
    return function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, scorefn)
        if speechKey ~= nil and #targets > 0 then
            Speak(ai, token, speechKey)
        end
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end
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

--How good a square is for this creature's next attack. Melee demons want an
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
local function RepositionPlan(ai, token, movement, flags, reserved, minimumGain)
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
            if utility > current + (minimumGain or 0.25) then
                candidates[#candidates+1] = {loc = loc, utility = utility, gain = utility - current}
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

--Squares claimed by the moves of one multi-creature effect, so two creatures
--never pick the same square. Forgotten once the effect has gone quiet.
local g_moveReservations = {squares = {}, time = 0}

local function MoveReservations()
    if dmhub.Time() - g_moveReservations.time > 5 then
        g_moveReservations.squares = {}
    end
    g_moveReservations.time = dmhub.Time()
    return g_moveReservations.squares
end

--Forced movement uses the shared handlers. When the target cannot be moved
--usefully, skip it rather than stall the turn on a Director prompt.
local function GenericForcedMovement(promptName, ai, invokerToken, casterToken, abilityClone, symbols, options)
    local generic = MonsterAI.prompts[promptName]
    local result = nil
    if generic ~= nil then
        result = generic.handler(ai, invokerToken, casterToken, abilityClone, symbols, options)
    end
    return result or {targets = {}}
end

for _,monsterType in ipairs({"Demon Ensnarer", "Demon Muceron"}) do
    MonsterAI:RegisterPrompt{
        id = monsterType .. ": Pull",
        prompts = {monsterType .. ":Pull!"},
        handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
            return GenericForcedMovement("Pull!", ai, invokerToken, casterToken, abilityClone, symbols, options)
        end,
    }
end

--Ranged demons would otherwise spend a spare maneuver walking into melee for
--the generic Knockback, Grab or Aid Attack. Off by default for them; the
--Monster AI panel can still turn them back on.
--The remasch is the same: it teleports away after striking, and walking back
--in for one of these would throw that away.
for _,monsterType in ipairs({"Demon Bendrak", "Demon Torlas", "Demon Remasch"}) do
    for _,moveid in ipairs({"Knockback", "Grab", "Aid Attack"}) do
        MonsterAI:SetMoveEnabledForMonster(monsterType, moveid, false)
    end
end

--Once a ranged demon has attacked, nothing else it can do scores, and the
--framework's fallback then walks it toward the nearest enemy -- into melee.
--Holding scores just above nothing whenever an enemy is already in its
--signature's range from where it stands, which keeps it there instead.
MonsterAI:RegisterMove{
    id = "Demon: Hold Range",
    category = "Maneuvers",
    monsters = rangedDemons,
    abilities = {},
    maxScore = 0.01,
    description = "A ranged demon with an enemy in range stays where it is instead of advancing into melee once it has nothing left to do.",
    score = function(self, ai, token)
        local profile = StrikeProfile(token)
        if profile.melee then
            return nil, "not a ranged demon"
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
-- Free strikes that follow a pull (Barbed Tongues).
--------------------------------------------------------------------------------

--The free strike a creature can make at this target where it stands, as the
--chooser wrapper's concrete ability, or nil.
local function FreeStrikeAt(casterToken, abilityClone, target, symbols)
    if not LiveCreature(target) or not CanSee(casterToken, target) then
        return nil
    end
    for _,synth in ipairs(abilityClone:SynthesizeAbilities(casterToken.properties) or {}) do
        if synth.targetType == "target"
            and MonsterAI.TargetDistance(synth:GetRangeSource(casterToken), target) <= synth:GetRange(casterToken.properties, symbols)
            and synth:TargetPassesFilter(casterToken, target, symbols or {}) then
            local activation = DeepCopy(synth)
            activation.disableSquadCoordination = true
            return activation
        end
    end
    return nil
end

--"If the target is pulled adjacent, the ensnarer can make a free strike
--against them": the data offers a free strike against anyone, so aim it at
--the creature the tongue struck, and only when it now stands adjacent.
local function TongueFreeStrikePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    local synthesized = abilityClone:SynthesizeAbilities(casterToken.properties) or {}
    if #synthesized == 0 then
        return nil
    end
    for _,target in ipairs(TargetsOfRunningCast(casterToken, "Barbed Tongues")) do
        if LiveCreature(target) and not target:IsFriend(casterToken)
            and MonsterAI.TargetDistance(casterToken, target) <= 1 then
            local strike = FreeStrikeAt(casterToken, abilityClone, target, symbols)
            if strike ~= nil then
                return {abilityOverride = strike, targets = {{token = target}}}
            end
        end
    end
    return {targets = {}}
end

MonsterAI:RegisterPrompt{
    id = "Demon Ensnarer: Barbed Tongues Free Strike",
    prompts = {"Demon Ensnarer:Invoked Ability", "Demon Ensnarer:Free Strike"},
    handler = TongueFreeStrikePrompt,
}

--Horrid Stench: an enemy with three or more pitlings within 2 squares can't
--regain Stamina. A pitling spitting from within 2 of an enemy that already
--has two others around it completes the stench, so it leans that way.
MonsterAI:RegisterTactic{
    id = "Demon Pitling: Horrid Stench",
    monsters = {"Demon Pitling"},
    description = "Pitlings prefer to spit from within 2 squares of an enemy that already has two other pitlings within 2, so it can't regain Stamina.",
    score = function(self, token, tokenLoc, enemy, ability)
        if enemy.isObject or enemy:Distance(tokenLoc) > 2 then
            return nil
        end
        local others = 0
        for _,other in ipairs(dmhub.allTokens) do
            if other.charid ~= token.charid and LiveCreature(other)
                and MonsterType(other) == "Demon Pitling" and other:Distance(enemy.loc) <= 2 then
                others = others + 1
            end
        end
        if others >= 2 then
            return 0.5
        end
    end,
}

--------------------------------------------------------------------------------
-- Ruinant.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Demon Ruinant: Bloodletting Claws",
    category = "Main Actions",
    monsters = {"Demon Ruinant"},
    abilities = {"Bloodletting Claws"},
    description = "Claw two enemies.",
    score = StrikeScore(1, DefaultTargetScore),
    execute = StrikeExecute(DefaultTargetScore),
}

--Enemies Salt Wounds can reach from where the ruinant stands (only those not
--at full Stamina pass its filter).
local function SaltWoundsTargets(token, ability)
    local range = ability:GetRange(token.properties)
    local result = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        if MonsterAI.TargetDistance(token, enemy) <= range and CanSee(token, enemy)
            and ability:TargetPassesFilter(token, enemy, {}) then
            result[#result+1] = enemy
        end
    end
    table.sort(result, function(a, b)
        return DefaultTargetScore(a, 0) > DefaultTargetScore(b, 0)
    end)
    table.resize_array(result, ability:GetNumTargets(token))
    return result
end

MonsterAI:RegisterMove{
    id = "Demon Ruinant: Salt Wounds",
    category = "Maneuvers",
    monsters = {"Demon Ruinant"},
    abilities = {"Salt Wounds"},
    description = "Spend 3 Malice to burn the wounds of up to three hurt enemies within 10, when at least two can be reached. Used after the claws.",
    score = function(self, ai, token, ability)
        local targets = SaltWoundsTargets(token, ability)
        if #targets < saltWoundsMinimumTargets then
            return nil, string.format("only %d hurt enemies in range", #targets)
        end
        return {score = 0.6 + (#targets - saltWoundsMinimumTargets)*0.1, targets = TokenTargets(targets)}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local targets = {}
        for _,enemy in ipairs(SaltWoundsTargets(token, ability)) do
            targets[#targets+1] = {token = enemy}
        end
        Speak(ai, token, "saltWounds")
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Torlas: Floor to Flesh and Grasping Tendons.
--------------------------------------------------------------------------------

--The squares each torlas has turned to flesh, by torlas charid. The morass
--lasts until the start of the torlas's next turn, which is when its own next
--Floor to Flesh replaces it.
local g_fleshSquares = {}

local function FleshSquares(invoker)
    local entry = invoker ~= nil and g_fleshSquares[invoker.charid] or nil
    if entry == nil or entry.round < CurrentRound() - 1 then
        return {}
    end
    return entry.squares
end

local function AllFleshSquares()
    local result = {}
    for _,entry in pairs(g_fleshSquares) do
        if entry.round >= CurrentRound() - 1 then
            for key,_ in pairs(entry.squares) do
                result[key] = true
            end
        end
    end
    return result
end

local function BuildCubeArea(token, ability, center, originLoc)
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(center),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        locOverride = originLoc,
        checklos = false,
        altitude = center.altitude * dmhub.unitsPerSquare,
    }
end

local function DestroyArea(area)
    if area ~= nil and type(area.Destroy) == "function" then
        area:Destroy()
    end
end

local function CubeTargets(token, ability, area)
    local result = {}
    local symbols = {mode = 1, targetArea = area}
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if LiveCreature(target) and ability:TargetPassesFilter(token, target, symbols) then
            result[#result+1] = {token = target}
        end
    end
    return result
end

--Demons inside the area are not slid, but the morass hurts them as they move
--through it too.
local function DemonsInArea(token, area)
    local result = 0
    for _,other in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if LiveCreature(other) and other:IsFriend(token) then
            result = result + 1
        end
    end
    return result
end

--The best 3 cube for Floor to Flesh: centred on or beside each enemy, cast
--from somewhere the torlas can reach with line of effect to the centre.
local function FindFloorToFleshPlan(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local pierceWalls = token.properties:GetPierceWalls()
    local origins = {}
    for _,info in pairs(ai.paths or {}) do
        origins[#origins+1] = {loc = info.loc, cost = info.cost or 0}
    end
    if #origins == 0 then
        origins[1] = {loc = token.loc, cost = 0}
    end
    table.sort(origins, function(a, b) return a.cost < b.cost end)

    local seen = {}
    local best = nil
    for _,enemy in ipairs(HostileCreatures(token)) do
        for dx=-1,1 do
            for dy=-1,1 do
                local center = enemy.loc:dir(dx, dy)
                local key = center.valid and LocKey(center) or nil
                if key ~= nil and not seen[key] then
                    seen[key] = true
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
                        local area = BuildCubeArea(token, ability, center, origin.loc)
                        local targets = CubeTargets(token, ability, area)
                        local demons = DemonsInArea(token, area)
                        DestroyArea(area)
                        local value = 0
                        for _,targetInfo in ipairs(targets) do
                            value = value + DefaultTargetScore(targetInfo.token, 0)
                        end
                        local utility = value - demons*0.3 - origin.cost*0.001
                        if #targets > 0 and (best == nil or utility > best.utility) then
                            best = {
                                loc = origin.loc,
                                center = center,
                                enemies = #targets,
                                demons = demons,
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

MonsterAI:RegisterMove{
    id = "Demon Torlas: Floor to Flesh",
    category = "Main Actions",
    monsters = {"Demon Torlas"},
    abilities = {"Floor to Flesh"},
    description = "Turn the ground under as many enemies as possible to flesh, then slide them through it.",
    score = function(self, ai, token, ability)
        local plan = FindFloorToFleshPlan(ai, token, ability)
        if plan == nil then
            return nil, "no enemy can be caught in the cube"
        end
        plan.score = 1 + math.min(0.4, (plan.enemies - 1)*0.2)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local area = BuildCubeArea(token, ability, scoringInfo.center, nil)
        local targets = CubeTargets(token, ability, area)
        if #targets == 0 then
            DestroyArea(area)
            return
        end
        --Remembered before the cast, because the slides it prompts for read it.
        local squares = {}
        for _,loc in ipairs(area.locations or {}) do
            squares[LocKey(loc)] = true
        end
        g_fleshSquares[token.charid] = {squares = squares, round = CurrentRound()}
        Speak(ai, token, "floorToFlesh")
        ai:ExecuteAbility(token, ability, targets, {
            sleep = abilityPause,
            symbols = {targetArea = area},
            targetArea = area,
        })
        DestroyArea(area)
    end,
}

--The demons a moved enemy would end next to: melee demons count fully, others a little.
local function DemonsBeside(invoker, loc, exclude)
    local result = 0
    for _,ally in ipairs(DemonAllies(invoker)) do
        if (exclude == nil or ally.charid ~= exclude.charid) and ally:Distance(loc) <= 1 then
            result = result + cond(StrikeProfile(ally).melee, 1, 0.3)
        end
    end
    return result
end

--Scores every legal destination of a forced move of the creature and returns
--the best, using a scoring function of (path, movementInfo, destination).
--A slide that stops short of its full distance asks the slid creature (not
--the demon) whether to "Continue sliding", a prompt no AI can answer; so a
--slide only stops short when it collides, and the furthest one is used when
--nothing else is possible.
local function BestForcedMoveDestination(casterToken, abilityClone, symbols, range, forcedMovement, scorefn)
    local predicate = abilityClone:TargetLocPassesFilterPredicate(casterToken, symbols)
        or function(_) return true end
    local shape = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = casterToken,
        radius = range,
        checklos = false,
    }
    forcedMovement = forcedMovement or (symbols ~= nil and symbols.forcedmovement) or abilityClone:try_get("forcedMovement", "slide")
    local isSlide = forcedMovement == "slide"
    local best = nil
    local furthest = nil
    for _,loc in ipairs(shape.locations or {}) do
        if predicate(loc) then
            local info = casterToken:MarkMovementArrow(loc, {
                straightline = true,
                ignorecreatures = false,
                forcedMovementDistance = range,
            })
            if info ~= nil and info.path ~= nil then
                local path = info.path
                local dist = path.destination:DistanceInTiles(path.origin)
                if dist > 0 then
                    local score = scorefn(path, info, path.destination, dist)
                    local complete = dist >= range or path.hasCollision or #(info.collideWith or {}) > 0
                    if (complete or not isSlide) and (best == nil or score > best.score) then
                        best = {loc = loc, score = score}
                    end
                    if furthest == nil or dist > furthest.dist or (dist == furthest.dist and score > furthest.score) then
                        furthest = {loc = loc, score = score, dist = dist}
                    end
                end
            end
        end
    end
    casterToken:ClearMovementArrow()
    return best or furthest
end

--What a collision or fall at the end of a forced move is worth to the demons.
local function CollisionValue(invoker, info, path)
    local value = 0
    for _,other in ipairs(info.collideWith or {}) do
        if other.isObject then
            value = value + 2
        elseif other:IsFriend(invoker) then
            value = value - 4
        else
            value = value + 1.5
        end
    end
    local fall = path.fallDistance or 0
    if fall >= 2 then
        value = value + fall
    end
    return value
end

local function StepsInSquares(path, squares)
    local result = 0
    for _,step in ipairs(path.steps or {}) do
        if squares[LocKey(step)] then
            result = result + 1
        end
    end
    return result
end

--Torlas forced movement: drag the enemy through the flesh (1 damage a square)
--and leave it in the morass or next to a melee demon, never next to the
--fragile torlas itself.
local function TorlasForcedMovePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken:IsFriend(invokerToken) then
        return GenericForcedMovement(abilityClone.name, ai, invokerToken, casterToken, abilityClone, symbols, options)
    end
    local range = abilityClone:GetRange(casterToken.properties)
    local flesh = AllFleshSquares()
    local best = BestForcedMoveDestination(casterToken, abilityClone, symbols, range, nil, function(path, info, destination, dist)
        local score = StepsInSquares(path, flesh)*1.5
            + cond(flesh[LocKey(destination)] == true, 1, 0)
            + math.min(2, DemonsBeside(invokerToken, destination, invokerToken))
            + CollisionValue(invokerToken, info, path)
            + dist*0.1
        if invokerToken:Distance(destination) <= 1 then
            score = score - 3
        end
        return score
    end)
    if best == nil then
        return {targets = {}}
    end
    casterToken:MarkMovementArrow(best.loc, {straightline = true, ignorecreatures = false, forcedMovementDistance = range})
    MonsterAI.Sleep(movementPause)
    casterToken:ClearMovementArrow()
    return {targets = {{loc = best.loc}}}
end

MonsterAI:RegisterPrompt{
    id = "Demon Torlas: Forced Movement",
    prompts = {"Demon Torlas:Slide!", "Demon Torlas:Pull!"},
    handler = TorlasForcedMovePrompt,
}

--Enemies Grasping Tendons should pull from where the torlas stands: those a
--pull would drag through flesh or next to a melee demon.
local function TendonsTargets(token, ability)
    local range = ability:GetRange(token.properties)
    local flesh = AllFleshSquares()
    local demons = DemonAllies(token)
    local result = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        if MonsterAI.TargetDistance(token, enemy) <= range and CanSee(token, enemy)
            and ability:TargetPassesFilter(token, enemy, {}) then
            local value = 0
            --Already in the flesh, or flesh between it and the torlas.
            for _,loc in ipairs(enemy.locsOccupying) do
                if flesh[LocKey(loc)] then
                    value = value + 2
                    break
                end
            end
            --A melee demon between the enemy and the torlas will be passed.
            for _,ally in ipairs(demons) do
                if ally.charid ~= token.charid and StrikeProfile(ally).melee
                    and ally:Distance(enemy.loc) <= 4
                    and token:Distance(ally.loc) < token:Distance(enemy.loc) then
                    value = value + 1
                    break
                end
            end
            --A pull lands an enemy that is too close right next to the torlas.
            if MonsterAI.TargetDistance(token, enemy) <= 3 then
                value = value - 2
            end
            if value > 0 then
                result[#result+1] = {token = enemy, value = value}
            end
        end
    end
    table.sort(result, function(a, b) return a.value > b.value end)
    table.resize_array(result, ability:GetNumTargets(token))
    return result
end

MonsterAI:RegisterMove{
    id = "Demon Torlas: Grasping Tendons",
    category = "Maneuvers",
    monsters = {"Demon Torlas"},
    abilities = {"Grasping Tendons"},
    description = "Pull up to three enemies through the flesh morass or into the reach of melee demons. Used after Floor to Flesh.",
    score = function(self, ai, token, ability)
        local targets = TendonsTargets(token, ability)
        if #targets == 0 then
            return nil, "no enemy worth pulling"
        end
        local value = 0
        for _,target in ipairs(targets) do
            value = value + target.value
        end
        return {score = 0.55 + math.min(0.3, value*0.05), targets = targets}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local targets = {}
        for _,target in ipairs(TendonsTargets(token, ability)) do
            targets[#targets+1] = {token = target.token}
        end
        if #targets == 0 then
            return
        end
        Speak(ai, token, "tendons")
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Bendrak: Warp Perceptions and Vanish.
--------------------------------------------------------------------------------

--True when this creature still has a turn coming this round: its initiative
--entry has not gone yet (or is going now and its signature is unused).
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

local invisibleConditionName = "Invisible"

local function IsHiddenOrInvisible(token)
    local ok, result = pcall(function()
        return token.properties:HasNamedCondition("Hidden") or token.properties:HasNamedCondition(invisibleConditionName)
    end)
    return ok and result == true
end

MonsterAI:RegisterMove{
    id = "Demon Bendrak: Warp Perceptions",
    category = "Main Actions",
    monsters = {"Demon Bendrak"},
    abilities = {"Warp Perceptions"},
    description = "Signature ranged strike.",
    score = StrikeScore(1, DefaultTargetScore),
    execute = StrikeExecute(DefaultTargetScore),
}

--How badly a demon needs to disappear: enemies near enough to reach it next
--round, more so when it is hurt.
local function VanishNeed(token, enemies)
    local nearest = NearestDistance(token.loc, enemies)
    if nearest > vanishThreatDistance then
        return 0
    end
    local need = 1 + AdjacentEnemiesAt(enemies, token.loc)*0.5
    if StaminaFraction(token) <= 0.5 then
        need = need + 1
    end
    if IsMinion(token) then
        need = need*0.3
    end
    --A demon still to act will step out of hiding to attack anyway.
    if StillToActThisRound(token) then
        need = need*0.6
    end
    return need
end

local function FindVanishTarget(token, ability)
    local enemies = HostileCreatures(token)
    local range = ability:GetRange(token.properties)
    local best = nil
    for _,ally in ipairs(DemonAllies(token)) do
        if not IsHiddenOrInvisible(ally)
            and (ally.charid == token.charid or (MonsterAI.TargetDistance(token, ally) <= range and CanSee(token, ally)))
            and ability:TargetPassesFilter(token, ally, {}) then
            local need = VanishNeed(ally, enemies)
            --Its own vanish also lets the bendrak keep hexing next round.
            if ally.charid == token.charid then
                need = need + 0.25
            end
            if need > 0 and (best == nil or need > best.need) then
                best = {token = ally, need = need}
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Demon Bendrak: Vanish",
    category = "Maneuvers",
    monsters = {"Demon Bendrak"},
    abilities = {"Vanish"},
    description = "Spend 1 Malice to make itself, or a hurt demon in the thick of it, vanish and slip away. Used after the bendrak's strike.",
    score = function(self, ai, token, ability)
        local target = FindVanishTarget(token, ability)
        if target == nil then
            return nil, "no demon is threatened"
        end
        return {score = 0.5 + math.min(0.25, target.need*0.08), target = target.token, targets = {{token = target.token}}}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local target = scoringInfo.target
        if not LiveCreature(target) then
            return
        end
        Speak(ai, token, "vanish")
        --The vanished demon answers its own "move up to 3 and hide" prompt.
        WithControlOf(ai, {target}, function()
            ai:ExecuteAbility(token, ability, {{token = target}}, {sleep = abilityPause})
        end)
    end,
}

--Where a vanished demon slips to: out of reach of enemies, and for a ranged
--demon still somewhere it can strike from next turn.
local function SlipAwayPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    local enemies = HostileCreatures(casterToken)
    local range = abilityClone:GetRange(casterToken.properties, symbols)
    local profile = StrikeProfile(casterToken)
    --A melee demon still to act this round stays in the fight, unseen.
    if profile.melee and StillToActThisRound(casterToken) and NearestDistance(casterToken.loc, enemies) <= profile.range then
        return {targets = {}}
    end
    local predicate = abilityClone:TargetLocPassesFilterPredicate(casterToken, symbols) or function(_) return true end
    local reserved = MoveReservations()
    local best = nil
    for _,info in pairs(casterToken:CalculatePathfindingArea(range*10, {"shift"})) do
        local loc = info.loc
        if loc ~= nil and LandingIsFree(casterToken, loc, reserved) and predicate(loc) then
            local nearest = NearestDistance(loc, enemies)
            local score = -AdjacentEnemiesAt(enemies, loc)*3 + math.min(nearest, 6)*0.3
            if not profile.melee and nearest <= profile.range then
                score = score + 1
            elseif profile.melee and nearest <= (casterToken.properties:CurrentMovementSpeed() or 5) + profile.range then
                score = score + 1
            end
            score = score - (info.cost or 0)*0.001
            if best == nil or score > best.score then
                best = {loc = loc, score = score}
            end
        end
    end
    if best == nil then
        return {targets = {}}
    end
    ReserveLanding(casterToken, best.loc, reserved)
    ShowMoveArrow(casterToken, best.loc)
    return {targets = {{loc = best.loc}}}
end

MonsterAI:RegisterPrompt{
    id = "Demon Bendrak: Vanish Shift and Hide",
    prompts = {"Demon Bendrak:Shift and Hide"},
    handler = SlipAwayPrompt,
}

--After the shift, the vanished demon attempts to hide. The prompt is named
--after whichever demon vanished.
local hidePrompts = {}
for _,monsterType in ipairs(demonMonsters) do
    hidePrompts[#hidePrompts+1] = monsterType .. ":Hide if in Cover or Concealment"
end

MonsterAI:RegisterPrompt{
    id = "Demon: Vanish Hide",
    prompts = hidePrompts,
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if casterToken.playerControlled then
            return nil
        end
        return {targets = {{token = casterToken}}}
    end,
}

--------------------------------------------------------------------------------
-- Remasch: Abyssal Strike and Grasping Shadow.
--------------------------------------------------------------------------------

--What each remasch means to do with its next teleport, by charid:
--{phase = "approach", target = token} before Grasping Shadow's strike, and
--{phase = "done"} once that strike is made.
--
--Abyssal Strike's 5 Malice rider (take an adjacent creature along) is not
--used: in the data its teleport is invoked with inherited targeting, which
--opens a Director prompt the AI cannot answer.
local g_remaschPlans = {}

local function GraspingShadowStillToCome(token)
    local ability = FindAbility(token, "Grasping Shadow")
    return ability ~= nil and ability:CanAfford(token)
end

--A landing square after Abyssal Strike: out of melee reach, and, when
--Grasping Shadow is still to come, within its 2-square teleport of an enemy.
local function RetreatScore(token, loc, enemies, wantsAnotherStrike)
    local adjacent = AdjacentEnemiesAt(enemies, loc)
    local nearest = NearestDistance(loc, enemies)
    local score = -adjacent*3
    local within2 = 0
    for _,enemy in ipairs(enemies) do
        if enemy:Distance(loc) <= 2 then
            within2 = within2 + 1
        end
    end
    score = score - within2*0.5
    if wantsAnotherStrike then
        if nearest <= 3 then
            score = score + 3
        end
    else
        --Ambushers like a little distance, but not so much they lose the fight.
        if nearest >= 3 and nearest <= 6 then
            score = score + 1
        end
    end
    return score
end

--The free squares the remasch could teleport to within range, with sight.
local function TeleportCandidates(casterToken, abilityClone, symbols, range)
    local predicate = abilityClone:TargetLocPassesFilterPredicate(casterToken, symbols) or function(_) return true end
    local shape = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = casterToken,
        radius = range,
        checklos = true,
    }
    local result = {}
    for _,loc in ipairs(shape.locations or {}) do
        if LandingIsFree(casterToken, loc) and predicate(loc) then
            result[#result+1] = loc
        end
    end
    return result
end

local function RemaschTeleportPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    local range = abilityClone:GetRange(casterToken.properties, symbols)
    local enemies = HostileCreatures(casterToken)
    local plan = g_remaschPlans[casterToken.charid]

    local best = nil
    for _,loc in ipairs(TeleportCandidates(casterToken, abilityClone, symbols, range)) do
        local score
        if plan ~= nil and plan.phase == "approach" and LiveCreature(plan.target) then
            score = cond(plan.target:Distance(loc) <= 1, 10, -plan.target:Distance(loc))
                - AdjacentEnemiesAt(enemies, loc)*0.5
        else
            local anotherStrike = (plan == nil or plan.phase ~= "done") and GraspingShadowStillToCome(casterToken)
            score = RetreatScore(casterToken, loc, enemies, anotherStrike)
        end
        score = score - casterToken.loc:DistanceInTiles(loc)*0.01
        if best == nil or score > best.score then
            best = {loc = loc, score = score}
        end
    end
    if plan ~= nil and plan.phase == "approach" then
        plan.phase = "strike"
    end
    if best == nil then
        return {targets = {}}
    end
    ShowMoveArrow(casterToken, best.loc)
    return {targets = {{loc = best.loc}}}
end

MonsterAI:RegisterPrompt{
    id = "Demon Remasch: Teleport",
    prompts = {"Demon Remasch:Teleport", "Demon Remasch:Teleport!"},
    handler = RemaschTeleportPrompt,
}

--Grasping Shadow opens with an empty wrapper that does nothing; other
--wrappers go to the shared handlers.
MonsterAI:RegisterPrompt{
    id = "Demon Remasch: Invoked Ability",
    prompts = {"Demon Remasch:Invoked Ability"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if #abilityClone:try_get("behaviors", {}) == 0 and abilityClone.targetType == "self" then
            return {targets = {{token = casterToken}}}
        end
        return nil
    end,
}

--Grasping Shadow's strike: the enemy the remasch teleported in beside.
MonsterAI:RegisterPrompt{
    id = "Demon Remasch: Grasping Shadow Strike",
    prompts = {"Demon Remasch:Abyssal Strike"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = g_remaschPlans[casterToken.charid]
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        local candidates = {}
        for _,enemy in ipairs(HostileCreatures(casterToken)) do
            if MonsterAI.TargetDistance(casterToken, enemy) <= range and CanSee(casterToken, enemy)
                and abilityClone:TargetPassesFilter(casterToken, enemy, symbols or {}) then
                candidates[#candidates+1] = enemy
            end
        end
        table.sort(candidates, function(a, b)
            local aPlanned = plan ~= nil and plan.target ~= nil and a.charid == plan.target.charid
            local bPlanned = plan ~= nil and plan.target ~= nil and b.charid == plan.target.charid
            if aPlanned ~= bPlanned then
                return aPlanned
            end
            return DefaultTargetScore(a, 0) > DefaultTargetScore(b, 0)
        end)
        --The strike's own teleport afterwards is a retreat: this was the
        --second strike.
        g_remaschPlans[casterToken.charid] = {phase = "done"}
        if #candidates == 0 then
            return {targets = {}}
        end
        symbols.mode = 1
        return {targets = {{token = candidates[1]}}}
    end,
}

MonsterAI:RegisterMove{
    id = "Demon Remasch: Abyssal Strike",
    category = "Main Actions",
    monsters = {"Demon Remasch"},
    abilities = {"Abyssal Strike"},
    description = "Strike, then teleport out of reach (or, with Grasping Shadow still to come, to within its reach of another enemy).",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, DefaultTargetScore)
        if loc == nil or targetScore == nil or targetScore <= 0 then
            return nil, "no enemy can be struck this turn"
        end
        return {
            score = 1 + math.min(0.2, math.max(0, targetScore - 1)*0.1),
            loc = loc,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, DefaultTargetScore)
        if #targets == 0 then
            return
        end
        g_remaschPlans[token.charid] = nil
        Speak(ai, token, "abyssalStrike")
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause, symbols = {mode = 1}})
    end,
}

--Grasping Shadow: the enemy the remasch can reach with a 2-square teleport.
local function GraspingShadowTarget(token)
    local strike = FindAbility(token, "Abyssal Strike")
    local reach = strike ~= nil and strike:GetRange(token.properties) or 1
    local best = nil
    for _,enemy in ipairs(HostileCreatures(token)) do
        if MonsterAI.TargetDistance(token, enemy) <= 2 + reach then
            --A free square beside it that the teleport can reach.
            for _,loc in ipairs(enemy.loc:LocsInRadius(reach) or {}) do
                if token:Distance(loc) <= 2 and LandingIsFree(token, loc) and token:GetLineOfSight(loc, token.properties:GetPierceWalls()) > 0 then
                    local score = DefaultTargetScore(enemy, 0)
                    if best == nil or score > best.score then
                        best = {token = enemy, score = score}
                    end
                    break
                end
            end
            if best == nil and MonsterAI.TargetDistance(token, enemy) <= reach then
                best = {token = enemy, score = DefaultTargetScore(enemy, 0)}
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Demon Remasch: Grasping Shadow",
    category = "Maneuvers",
    monsters = {"Demon Remasch"},
    abilities = {"Grasping Shadow"},
    description = "Spend 3 Malice to teleport beside an enemy and make a second Abyssal Strike, after the remasch's own.",
    score = function(self, ai, token, ability)
        local strike = FindAbility(token, "Abyssal Strike")
        --Its own strike first: it is free, and its teleport sets this one up.
        if strike ~= nil and strike:CanAfford(token) then
            local loc = ai:FindBestMoveToUseStrike(token, strike, DefaultTargetScore)
            if loc ~= nil then
                return nil, "Abyssal Strike comes first"
            end
        end
        local target = GraspingShadowTarget(token)
        if target == nil then
            return nil, "no enemy within a 2-square teleport of reach"
        end
        return {score = 0.9, target = target.token, targets = {{token = target.token}}}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local target = scoringInfo.target
        if not LiveCreature(target) then
            return
        end
        g_remaschPlans[token.charid] = {phase = "approach", target = target}
        Speak(ai, token, "graspingShadow")
        local ok, err = pcall(function()
            ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        end)
        g_remaschPlans[token.charid] = nil
        if not ok then
            error(err)
        end
    end,
}

--------------------------------------------------------------------------------
-- Muceron: Barbed Tongues and Tongue Pull.
--------------------------------------------------------------------------------

--Barbed Tongues reaches 2: striking from 2 away pulls the enemy adjacent,
--which earns the free strike or grab, so the muceron prefers that square.
local function FindBarbedTonguesPlan(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local enemies = HostileCreatures(token)
    local flesh = AllFleshSquares()
    --Walking away from adjacent enemies provokes their opportunity attacks.
    local adjacentNow = AdjacentEnemiesAt(enemies, token.loc)
    local best = nil
    for _,info in pairs(ai.paths or {}) do
        local moving = LocKey(info.loc) ~= LocKey(token.loc)
        local squareScore = -(info.cost or 0)*0.001
        if moving then
            squareScore = squareScore - adjacentNow*0.35
        end
        if flesh[LocKey(info.loc)] then
            squareScore = squareScore - 0.3
        end
        for _,targetInfo in ipairs(ai:FindValidTargetsOfStrike(token, ability, info.loc, range)) do
            local target = targetInfo.token
            local score = DefaultTargetScore(target, targetInfo.edges) + squareScore
            if not target.isObject then
                --Striking from 2 away pulls the enemy adjacent, unless its
                --stability eats the pull (2 at tier 1, 3 at tier 2).
                local distance = ai:TargetDistanceFromLoc(token, target, info.loc)
                local stability = 0
                pcall(function() stability = target.properties:Stability() or 0 end)
                if distance >= 2 and stability <= 1 then
                    score = score + 0.4
                elseif distance >= 2 and stability == 2 then
                    score = score + 0.2
                end
            end
            if best == nil or score > best.score then
                best = {loc = info.loc, target = target, score = score}
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Demon Muceron: Barbed Tongues",
    category = "Main Actions",
    monsters = {"Demon Muceron"},
    abilities = {"Barbed Tongues"},
    description = "Lash an enemy from 2 squares away so the pull drags them adjacent for a free strike or grab.",
    score = function(self, ai, token, ability)
        local plan = FindBarbedTonguesPlan(ai, token, ability)
        if plan == nil then
            return nil, "no enemy can be struck this turn"
        end
        plan.score = 1 + math.min(0.2, math.max(0, plan.score - 1)*0.1)
        plan.targets = {{token = plan.target}}
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local target = scoringInfo.target
        local targets = nil
        for _,info in ipairs(ai:FindValidTargetsOfStrike(token, ability, token.loc)) do
            if target ~= nil and info.token.charid == target.charid then
                targets = {info}
            end
        end
        if targets == nil then
            targets = SortedStrikeTargets(ai, token, ability, token.loc, DefaultTargetScore)
        end
        Speak(ai, token, "tongue")
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

local function IsGrabbing(token)
    local grabbing = false
    local conditions = dmhub.GetTable(CharacterCondition.tableName) or {}
    pcall(function()
        token.properties:VisitConditionCasterSource(function(conditionid, targetToken)
            local condition = conditions[conditionid]
            if condition ~= nil and condition.name == "Grabbed" and LiveCreature(targetToken) then
                grabbing = true
            end
        end)
    end)
    return grabbing
end

--The muceron's follow-up once the tongue drags its target adjacent: grab it
--when other demons are close enough to pile on and the muceron's hands are
--free, otherwise take the free strike.
local function MuceronFollowUpMode(muceron, target)
    if target == nil or IsGrabbing(muceron) then
        return 1
    end
    for _,ally in ipairs(DemonAllies(muceron)) do
        if ally.charid ~= muceron.charid and ally:Distance(target.loc) <= 2 then
            return 2
        end
    end
    return 1
end

local function TongueTarget(casterToken)
    for _,target in ipairs(TargetsOfRunningCast(casterToken, "Barbed Tongues")) do
        if LiveCreature(target) and not target:IsFriend(casterToken)
            and MonsterAI.TargetDistance(casterToken, target) <= 1 then
            return target
        end
    end
    return nil
end

--The tongue's follow-up comes as three prompts: the Free Strike / Grab
--choice (an "Invoked Ability" on the muceron with two modes), then the free
--strike's chooser or the Grab itself, each aimed at the pulled creature.
MonsterAI:RegisterPrompt{
    id = "Demon Muceron: Barbed Tongues Follow-up",
    prompts = {"Demon Muceron:Invoked Ability", "Demon Muceron:Free Strike"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if casterToken.playerControlled then
            return nil
        end
        local target = TongueTarget(casterToken)
        if target == nil then
            return {targets = {}}
        end
        local modes = abilityClone:try_get("modeList")
        if abilityClone:try_get("multipleModes", false) == true and type(modes) == "table" and #modes >= 2 then
            symbols.mode = MuceronFollowUpMode(casterToken, target)
            return {targets = {{token = casterToken}}}
        end
        local strike = FreeStrikeAt(casterToken, abilityClone, target, symbols)
        if strike ~= nil then
            return {abilityOverride = strike, targets = {{token = target}}}
        end
        return {targets = {}}
    end,
}

MonsterAI:RegisterPrompt{
    id = "Demon Muceron: Barbed Tongues Grab",
    prompts = {"Demon Muceron:Grab"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local target = TongueTarget(casterToken)
        if target == nil then
            return {targets = {}}
        end
        return {targets = {{token = target}}}
    end,
}

local function TonguePullTargets(token, ability)
    local range = ability:GetRange(token.properties)
    local result = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        local distance = MonsterAI.TargetDistance(token, enemy)
        if distance > 1 and distance <= range and CanSee(token, enemy)
            and ability:TargetPassesFilter(token, enemy, {}) then
            result[#result+1] = enemy
        end
    end
    table.sort(result, function(a, b)
        return DefaultTargetScore(a, 0) > DefaultTargetScore(b, 0)
    end)
    table.resize_array(result, ability:GetNumTargets(token))
    return result
end

MonsterAI:RegisterMove{
    id = "Demon Muceron: Tongue Pull",
    category = "Maneuvers",
    monsters = {"Demon Muceron"},
    abilities = {"Tongue Pull"},
    description = "Spend 2 Malice to drag up to three enemies within 5 to the muceron and its allies, when at least two are out of reach. Used after the tongue strike.",
    score = function(self, ai, token, ability)
        local targets = TonguePullTargets(token, ability)
        if #targets < tongueMinimumTargets then
            return nil, string.format("only %d enemies to pull", #targets)
        end
        return {score = 0.6 + (#targets - tongueMinimumTargets)*0.1, targets = TokenTargets(targets)}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local targets = {}
        for _,enemy in ipairs(TonguePullTargets(token, ability)) do
            targets[#targets+1] = {token = enemy}
        end
        if #targets == 0 then
            return
        end
        Speak(ai, token, "tongue")
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Chorogaunt.
--------------------------------------------------------------------------------

--Enemies the chorogaunt's harmony would catch from loc.
local function HarmonyCatches(ai, token, ability, loc)
    local range = ability:GetRange(token.properties)
    local symbols = {mode = 1}
    local result = 0
    ai:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        for _,enemy in ipairs(HostileCreatures(token)) do
            if MonsterAI.TargetDistance(enemy, token) <= range and ability:TargetPassesFilter(token, enemy, symbols) then
                result = result + 1
            end
        end
    end)
    return result
end

--Each chorogaunt that has just slid enemies into place for its harmony.
local g_harmonyPending = {}

MonsterAI:RegisterMove{
    id = "Chorogaunt: Agonizing Harmony",
    category = "Main Actions",
    monsters = chorogaunts,
    abilities = {"Agonizing Harmony"},
    description = "Catch as many enemies as possible in the psychic burst; its free ally shift goes to whichever demon gains most from it.",
    score = function(self, ai, token, ability)
        local loc, caught = ai:FindBestMoveToUseBurst(token, ability, function(target)
            if LiveCreature(target) and not target:IsFriend(token) then
                return 1
            end
            return 0
        end)
        if loc == nil or caught == nil or caught <= 0 then
            return nil, "no enemy can be caught in the burst"
        end
        return {score = 1 + math.min(0.5, (caught - 1)*0.15), loc = loc, caught = caught}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        g_harmonyPending[token.charid] = nil
        Speak(ai, token, "harmony")
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--Agonizing Harmony's "one ally within 10 shifts up to their speed": the demon
--whose next attack improves most, non-minions first.
local function BestAllyToShift(ai, chorogaunt, range)
    local reserved = MoveReservations()
    local best = nil
    for _,ally in ipairs(DemonAllies(chorogaunt)) do
        if ally.charid ~= chorogaunt.charid and MonsterAI.TargetDistance(chorogaunt, ally) <= range then
            local speed = ally.properties:CurrentMovementSpeed() or 0
            local plan = RepositionPlan(ai, ally, speed, {"shift"}, reserved)
            if plan ~= nil then
                local value = plan.gain*cond(IsMinion(ally), 0.5, 1)
                if best == nil or value > best.value then
                    best = {token = ally, plan = plan, value = value}
                end
            end
        end
    end
    return best
end

--Planned shift squares for allies handed Agonizing Harmony's shift, by charid.
local g_allyShiftPlans = {}

local function AllyShiftPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    local range = abilityClone:GetRange(casterToken.properties, symbols)
    local best = BestAllyToShift(ai, casterToken, range)
    if best == nil then
        return {targets = {}}
    end
    g_allyShiftPlans[best.token.charid] = best.plan.loc
    ReserveLanding(best.token, best.plan.loc, MoveReservations())
    return {targets = {{token = best.token}}}
end

MonsterAI:RegisterPrompt{
    id = "Chorogaunt: Ally Shift",
    prompts = {"Demon Chorogaunt:Ally Shift", "Lesser Demon Chorogaunt:Ally Shift"},
    handler = AllyShiftPrompt,
}

--The Lesser Demon Chorogaunt's data names the same ally picker "Invoked
--Ability"; other wrappers of that name go to the shared handlers.
MonsterAI:RegisterPrompt{
    id = "Chorogaunt: Ally Shift (Invoked Ability)",
    prompts = {"Demon Chorogaunt:Invoked Ability", "Lesser Demon Chorogaunt:Invoked Ability"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if abilityClone.targetType == "target" and abilityClone:try_get("targetAllegiance") == "ally" then
            return AllyShiftPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
        end
        return nil
    end,
}

--The square from which the chorogaunt's harmony catches the most enemies,
--within a shift of distance squares.
local function HarmonyShiftPlan(ai, token, distance)
    local harmony = FindAbility(token, "Agonizing Harmony")
    if harmony == nil then
        return nil
    end
    local enemies = HostileCreatures(token)
    local best = nil
    for _,info in pairs(token:CalculatePathfindingArea(distance*10, {"shift"})) do
        local loc = info.loc
        if loc ~= nil and (LocKey(loc) == LocKey(token.loc) or LandingIsFree(token, loc)) then
            local score = HarmonyCatches(ai, token, harmony, loc)*10
                - AdjacentEnemiesAt(enemies, loc)*0.5 - (info.cost or 0)*0.001
            if best == nil or score > best.score then
                best = {loc = loc, score = score}
            end
        end
    end
    return best
end

--Shifts the chorogaunt hands out. Its own (Running Cacophony) go wherever the
--next harmony catches most; an ally's goes where Ally Shift planned it.
local function ChorogauntShiftPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken.playerControlled then
        return nil
    end
    local distance = abilityClone:GetRange(casterToken.properties, symbols)
    local loc = nil
    if IsChorogaunt(casterToken) and casterToken.charid == invokerToken.charid then
        local plan = HarmonyShiftPlan(ai, casterToken, distance)
        if plan ~= nil and LocKey(plan.loc) ~= LocKey(casterToken.loc) then
            loc = plan.loc
        end
    else
        loc = g_allyShiftPlans[casterToken.charid]
        g_allyShiftPlans[casterToken.charid] = nil
        if loc == nil or not LandingIsFree(casterToken, loc) then
            local plan = RepositionPlan(ai, casterToken, distance, {"shift"}, nil)
            loc = plan ~= nil and plan.loc or nil
        end
    end
    if loc == nil then
        return {targets = {}}
    end
    ShowMoveArrow(casterToken, loc)
    return {targets = {{loc = loc}}}
end

--The shift prompt is named after whichever creature invokes it: the
--chorogaunt itself, or the ally it handed the shift to.
local function QualifiedPrompts(name)
    local result = {}
    for _,monsterType in ipairs(demonMonsters) do
        result[#result+1] = monsterType .. ":" .. name
    end
    return result
end

MonsterAI:RegisterPrompt{
    id = "Chorogaunt: Shift",
    prompts = QualifiedPrompts("Shift"),
    handler = ChorogauntShiftPrompt,
}

--Chaotic Entrancing Harmony: slide an enemy into the coming harmony's burst,
--next to melee demons, or into something hard.
local function EntrancingSlidePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if casterToken:IsFriend(invokerToken) then
        return {targets = {}}
    end
    local range = abilityClone:GetRange(casterToken.properties)
    local harmony = FindAbility(invokerToken, "Agonizing Harmony")
    local harmonyRange = harmony ~= nil and harmony:GetRange(invokerToken.properties) or 0
    local harmonyNext = g_harmonyPending[invokerToken.charid] == true
    local reserved = MoveReservations()
    local best = BestForcedMoveDestination(casterToken, abilityClone, symbols, range, nil, function(path, info, destination, dist)
        if reserved[LocKey(destination)] then
            return -100
        end
        local score = math.min(2, DemonsBeside(invokerToken, destination, nil))
            + CollisionValue(invokerToken, info, path)
            + dist*0.05
        if harmonyNext and invokerToken:Distance(destination) <= harmonyRange then
            score = score + 3
        end
        return score
    end)
    if best == nil or best.score <= 0 then
        return {targets = {}}
    end
    reserved[LocKey(best.loc)] = true
    casterToken:MarkMovementArrow(best.loc, {straightline = true, ignorecreatures = false, forcedMovementDistance = range})
    MonsterAI.Sleep(stationaryPause)
    casterToken:ClearMovementArrow()
    return {targets = {{loc = best.loc}}}
end

MonsterAI:RegisterPrompt{
    id = "Chorogaunt: Entrancing Slide",
    prompts = {"Demon Chorogaunt:Slide!", "Lesser Demon Chorogaunt:Slide!"},
    handler = EntrancingSlidePrompt,
}

--How many more enemies the harmony would catch, and how many would end next
--to a melee demon, if each enemy in the entrancing burst slid toward the
--chorogaunt as far as it can.
local function EntrancingValue(token, ability)
    local range = ability:GetRange(token.properties)
    local slide = 3
    local harmony = FindAbility(token, "Agonizing Harmony")
    local harmonyRange = harmony ~= nil and harmony:GetRange(token.properties) or 0
    local harmonyReady = harmony ~= nil and harmony:CanAfford(token)
    local gained = 0
    local besideDemons = 0
    local caught = 0
    for _,enemy in ipairs(HostileCreatures(token)) do
        local distance = MonsterAI.TargetDistance(token, enemy)
        if distance <= range then
            caught = caught + 1
            if harmonyReady and distance > harmonyRange and distance - slide <= harmonyRange then
                gained = gained + 1
            end
            for _,ally in ipairs(DemonAllies(token)) do
                if ally.charid ~= token.charid and StrikeProfile(ally).melee
                    and ally:Distance(enemy.loc) > 1 and ally:Distance(enemy.loc) <= slide + 1 then
                    besideDemons = besideDemons + 1
                    break
                end
            end
        end
    end
    return gained, besideDemons, caught
end

MonsterAI:RegisterMove{
    id = "Chorogaunt: Chaotic Entrancing Harmony",
    category = "Maneuvers",
    monsters = chorogaunts,
    abilities = {"Chaotic Entrancing Harmony"},
    description = "Slide every enemy in the burst: before Agonizing Harmony when it pulls more enemies into the harmony's reach, otherwise into the arms of melee demons.",
    score = function(self, ai, token, ability)
        local gained, besideDemons, caught = EntrancingValue(token, ability)
        if caught == 0 then
            return nil, "no enemy in the burst"
        end
        if gained > 0 then
            return {score = 1.2 + math.min(0.3, gained*0.1), gained = gained, harmonyNext = true}
        end
        if besideDemons > 0 then
            return {score = 0.5 + math.min(0.3, besideDemons*0.1), besideDemons = besideDemons}
        end
        return nil, "sliding gains nothing"
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        g_harmonyPending[token.charid] = scoringInfo.harmonyNext == true or nil
        Speak(ai, token, "entrancing")
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--I Thrive on Pain: halve a strike's damage and hit 3 harder until the end of
--the chorogaunt's next turn.
MonsterAI:RegisterTrigger{
    id = "Chorogaunt: I Thrive on Pain",
    monsters = chorogaunts,
    abilities = {"I Thrive on Pain"},
    triggers = {"I Thrive on Pain"},
    description = "Spend 3 Malice to halve a strike's damage whenever Malice is plentiful, and always once the chorogaunt is winded.",
    handler = function(ai, token, triggerInfo)
        local malice = CharacterResource.GetMalice()
        if malice < 3 then
            return {dismiss = true}
        end
        if malice >= thriveFreeMalice or StaminaFraction(token) <= 0.5 then
            return {activate = true}
        end
        return {dismiss = true}
    end,
}

--------------------------------------------------------------------------------
-- Chorogaunt villain actions.
--------------------------------------------------------------------------------

local function EnemiesInRangeAndSight(token, ability)
    local range = ability:GetRange(token.properties)
    local result = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        if MonsterAI.TargetDistance(token, enemy) <= range and CanSee(token, enemy)
            and ability:TargetPassesFilter(token, enemy, {}) then
            result[#result+1] = enemy
        end
    end
    table.sort(result, function(a, b)
        return DefaultTargetScore(a, 0) > DefaultTargetScore(b, 0)
    end)
    table.resize_array(result, ability:GetNumTargets(token))
    return result
end

MonsterAI:RegisterVillainAction{
    id = "Chorogaunt: Frightening Tones",
    monsters = chorogaunts,
    abilities = {"Frightening Tones"},
    description = "Make three enemies within 10 choose between psychic damage and fear.",
    score = function(self, ai, token, ability, context)
        local targets = EnemiesInRangeAndSight(token, ability)
        if #targets == 0 then
            return nil, "no enemy in range"
        end
        return {score = math.min(1, 0.45 + #targets*0.15), targets = TokenTargets(targets)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,enemy in ipairs(EnemiesInRangeAndSight(token, ability)) do
            targets[#targets+1] = {token = enemy}
        end
        Speak(ai, token, "frighteningTones")
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

--Frightening Tones' choice belongs to each target, but the data asks the
--Director for it. The AI answers as a sensible hero would: shrug off 5 psychic
--damage while healthy, take the fear when it would hurt too much.
local function FrightenedTonesPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    --The invoke bakes the target's id into each choice's target filter, so
    --the target is whichever creature that filter accepts.
    local modes = abilityClone:try_get("modeList", {})
    local probe = modes[1] ~= nil and abilityClone:SwitchModes(1) or nil
    local target = nil
    for _,other in ipairs(HostileCreatures(casterToken)) do
        if probe ~= nil and probe ~= abilityClone and probe:TargetPassesFilter(casterToken, other, symbols or {}) then
            target = other
            break
        end
    end
    if target == nil then
        return nil
    end
    local healthy =target.properties:CurrentHitpoints() > 15 and StaminaFraction(target) > 0.4
    local wanted = cond(healthy, "5 Psychic Damage", "Frightened")
    for index,mode in ipairs(abilityClone:try_get("modeList", {})) do
        if mode.text == wanted then
            local variation = abilityClone:SwitchModes(index)
            if variation ~= nil then
                return {abilityOverride = variation, targets = {{token = target}}}
            end
        end
    end
    return nil
end

MonsterAI:RegisterPrompt{
    id = "Chorogaunt: Frightened Tones Choice",
    prompts = {"Demon Chorogaunt:Frightened Tones", "Lesser Demon Chorogaunt:Frightened Tones"},
    handler = FrightenedTonesPrompt,
}

--The ally Bully the Weak is killing, by chorogaunt charid: it is still on the
--map when the rest of the allies are chosen for the extra damage.
local g_bullyVictims = {}

--Bully the Weak kills one ally: the demon minion worth least (furthest from
--any enemy), or failing that the weakest non-minion that is nearly dead anyway.
local function FindBullyVictim(token, ability)
    local range = ability:GetRange(token.properties)
    local enemies = HostileCreatures(token)
    local best = nil
    for _,ally in ipairs(DemonAllies(token)) do
        if ally.charid ~= token.charid and MonsterAI.TargetDistance(token, ally) <= range
            and ability:TargetPassesFilter(token, ally, {}) then
            local worth
            if IsMinion(ally) then
                worth = 1 + math.max(0, 6 - NearestDistance(ally.loc, enemies))*0.2
            elseif StaminaFraction(ally) <= 0.25 then
                worth = 3 + ally.properties:CurrentHitpoints()*0.1
            end
            if worth ~= nil and (best == nil or worth < best.worth) then
                best = {token = ally, worth = worth}
            end
        end
    end
    return best
end

--Allies who will still strike this round with the bully's extra damage.
local function AlliesStillToStrike(token)
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return 0
    end
    local count = 0
    for _,ally in ipairs(DemonAllies(token)) do
        if ally.charid ~= token.charid then
            --An entry that has not gone yet this round still reads this round.
            local initiativeid = InitiativeQueue.GetInitiativeId(ally)
            local entry = initiativeid ~= nil and queue.entries[initiativeid] or nil
            if entry ~= nil and (tonumber(entry.round) or 0) <= queue.round then
                count = count + 1
            end
        end
    end
    return count
end

MonsterAI:RegisterVillainAction{
    id = "Chorogaunt: Bully the Weak",
    monsters = chorogaunts,
    abilities = {"Bully the Weak"},
    description = "Kill the least useful demon minion for Malice and +3 damage on every other demon's strikes this round.",
    score = function(self, ai, token, ability, context)
        local victim = FindBullyVictim(token, ability)
        if victim == nil then
            return nil, "no expendable ally in range"
        end
        local strikers = AlliesStillToStrike(token) - 1
        local score = 0.55 + math.max(0, strikers)*0.08
        if not IsMinion(victim.token) then
            score = score - 0.15
        end
        return {score = math.min(0.95, score), victim = victim.token, targets = {{token = victim.token}}}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local victim = scoringInfo.victim
        if not LiveCreature(victim) then
            return
        end
        Speak(ai, token, "bullyTheWeak")
        g_bullyVictims[token.charid] = victim.charid
        local ok, err = pcall(WithOwnMinionDeathsResolved, ai, token, victim, function()
            ai:ExecuteAbility(token, ability, {{token = victim}}, {sleep = abilityPause})
        end)
        g_bullyVictims[token.charid] = nil
        if not ok then
            error(err)
        end
    end,
}

--Running Cacophony uses Agonizing Harmony twice by name: each one catches
--every enemy in the burst from wherever the shift left the chorogaunt.
MonsterAI:RegisterPrompt{
    id = "Chorogaunt: Running Cacophony Harmony",
    prompts = {"Demon Chorogaunt:Agonizing Harmony", "Lesser Demon Chorogaunt:Agonizing Harmony"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        local targets = {}
        for _,enemy in ipairs(HostileCreatures(casterToken)) do
            if MonsterAI.TargetDistance(enemy, casterToken) <= range
                and abilityClone:TargetPassesFilter(casterToken, enemy, symbols or {}) then
                targets[#targets+1] = {token = enemy}
            end
        end
        Speak(ai, casterToken, "harmony")
        return {targets = targets}
    end,
}

--Bully the Weak's second half: every other ally in the encounter gets the
--extra damage (the Malice gain rides along on the caster).
MonsterAI:RegisterPrompt{
    id = "Chorogaunt: Bully the Weak Allies",
    prompts = {"Demon Chorogaunt:Bully the Weak", "Lesser Demon Chorogaunt:Bully the Weak"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        local targets = {}
        for _,ally in ipairs(dmhub.allTokens) do
            if LiveCreature(ally) and ally.charid ~= casterToken.charid and ally:IsFriend(casterToken)
                and ally.charid ~= g_bullyVictims[casterToken.charid]
                and InCombat(ally) and MonsterAI.TargetDistance(casterToken, ally) <= range
                and abilityClone:TargetPassesFilter(casterToken, ally, symbols or {}) then
                targets[#targets+1] = {token = ally}
            end
        end
        return {targets = targets}
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Chorogaunt: Running Cacophony",
    monsters = chorogaunts,
    abilities = {"Running Cacophony"},
    description = "Shift, Agonizing Harmony, shift, Agonizing Harmony: better the more enemies are near.",
    score = function(self, ai, token, ability, context)
        local harmony = FindAbility(token, "Agonizing Harmony")
        if harmony == nil then
            return nil, "no Agonizing Harmony"
        end
        local speed = token.properties:CurrentMovementSpeed() or 0
        local reach = harmony:GetRange(token.properties) + speed
        local near = 0
        for _,enemy in ipairs(HostileCreatures(token)) do
            if MonsterAI.TargetDistance(token, enemy) <= reach then
                near = near + 1
            end
        end
        if near == 0 then
            return nil, "no enemy within a shift of the harmony"
        end
        return {score = math.min(1, 0.55 + near*0.15), enemies = near}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, "runningCacophony")
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Start-of-turn Demon Malice features.
--------------------------------------------------------------------------------

--How much the acting demons gain from a double edge this turn: one per roll
--they will make. A non-minion that can attack makes one (the chorogaunt's
--burst hits many, so counts double); a minion squad makes one shared roll
--however many members are in reach.
local function SoulburnValue(context)
    local value = 0
    local squadsCounted = {}
    for _,actor in ipairs(context.actingTokens or {}) do
        if IsDemon(actor) then
            local enemies = HostileCreatures(actor)
            local speed = actor.properties:CurrentMovementSpeed() or 0
            local profile = StrikeProfile(actor)
            if NearestDistance(actor.loc, enemies) <= speed + profile.range + 1 then
                if IsMinion(actor) then
                    local squad = actor.properties:MinionSquad() or actor.charid
                    if not squadsCounted[squad] then
                        squadsCounted[squad] = true
                        value = value + 1
                    end
                elseif IsChorogaunt(actor) then
                    value = value + 2
                else
                    value = value + 1
                end
            end
        end
    end
    return value
end

local function ExecuteMapAbility(ai, caster, ability, targetTokens)
    local area = dmhub.CalculateShape{
        shape = "map",
        token = caster,
    }
    local targets = {}
    for _,target in ipairs(targetTokens) do
        if LiveCreature(target) then
            targets[#targets+1] = {token = target}
        end
    end
    ai:ExecuteAbility(caster, DeepCopy(ability), targets, {
        sleep = abilityPause,
        symbols = {targetArea = area},
        targetArea = area,
    })
end

MonsterAI:RegisterMaliceAbility{
    id = "Demon Malice: Soulburn",
    monsterGroups = demonGroup,
    abilities = {"Soulburn"},
    description = "Spend 3 Malice for a double edge when the acting demons will make enough attacks to use it.",
    score = function(self, ai, token, ability, context)
        local value = SoulburnValue(context)
        if value < 1.5 then
            return nil, string.format("acting demons' attacks are worth only %.1f", value)
        end
        return {score = math.min(0.9, 0.5 + value*0.12), value = value}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        --"Each demon acting this turn", the caster among them. (The map
        --target filter alone would reach every demon and leave out the caster.)
        local targets = {}
        for _,other in ipairs(context.actingTokens or {}) do
            if IsDemon(other) then
                targets[#targets+1] = other
            end
        end
        if #targets == 0 then
            targets[1] = token
        end
        Speak(ai, token, "soulburn")
        ExecuteMapAbility(ai, token, ability, targets)
    end,
}

--Abyssal Evolution: the demon minion that will do the most as a horde demon,
--the one closest to the enemy. A minion alone in its squad is preferred: it
--is about to die anyway.
local function FindEvolutionCandidate(token, ability)
    local best = nil
    for _,ally in ipairs(DemonAllies(token)) do
        if IsMinion(ally) and ability:TargetPassesFilter(token, ally, {}) then
            local enemies = HostileCreatures(ally)
            local score = -NearestDistance(ally.loc, enemies)
            if best == nil or score > best.score then
                best = {token = ally, score = score}
            end
        end
    end
    return best
end

MonsterAI:RegisterMaliceAbility{
    id = "Demon Malice: Abyssal Evolution",
    monsterGroups = demonGroup,
    abilities = {"Abyssal Evolution"},
    description = "Spend 7 Malice to turn the demon minion nearest the enemy into a horde demon, from round 2 on.",
    score = function(self, ai, token, ability, context)
        if (context.round or 1) < 2 then
            return nil, "minions are still fresh in round 1"
        end
        local candidate = FindEvolutionCandidate(token, ability)
        if candidate == nil then
            return nil, "no demon minion to evolve"
        end
        return {score = 0.7, minion = candidate.token}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local minion = scoringInfo.minion
        if not LiveCreature(minion) then
            return
        end
        --The summon would ask the Director to pick the new demon in a dialog.
        --Narrow it to the one the AI wants: a ruinant to fight in melee, or a
        --torlas in place of a ranged minion.
        local evolved = cond(StrikeProfile(minion).melee, "Demon Ruinant", "Demon Torlas")
        local cast = DeepCopy(ability)
        --The data summons it with no initiative entry, so it would never
        --act; give it a fresh entry of its own.
        for _,behavior in ipairs(cast.behaviors or {}) do
            if behavior.typeName == "ActivatedAbilitySummonBehavior" then
                behavior.bestiaryFilter = string.format('beast.name = "%s"', evolved)
                behavior.newInitiativeGroup = true
            end
        end
        Speak(ai, token, "evolution")
        WithOwnMinionDeathsResolved(ai, token, minion, function()
            ai:ExecuteAbility(token, cast, {{token = minion}}, {sleep = abilityPause, symbols = {mode = 1}})
        end)
    end,
}

--Abyssal Rift: two 2x2 rifts where heroes will walk into them, beside the
--heroes nearest the demons.
local function RiftSquares(token, count)
    local reserved = {}
    local result = {}
    local enemies = HostileCreatures(token)
    table.sort(enemies, function(a, b)
        return NearestDistance(a.loc, DemonAllies(token)) < NearestDistance(b.loc, DemonAllies(token))
    end)
    for _,enemy in ipairs(enemies) do
        if #result >= count then
            break
        end
        for _,loc in ipairs(enemy.loc:LocsInRadius(2) or {}) do
            local block = {loc, loc.east, loc.south, loc.east.south}
            local free = true
            for _,square in ipairs(block) do
                if not square.valid or reserved[LocKey(square)] then
                    free = false
                    break
                end
                for _,other in ipairs(dmhub.GetTokensAtLoc(square) or {}) do
                    if other.valid then
                        free = false
                    end
                end
            end
            if free then
                for _,square in ipairs(block) do
                    reserved[LocKey(square)] = true
                end
                result[#result+1] = {loc = loc}
                break
            end
        end
    end
    return result
end

local function RiftsOnMap()
    local result = 0
    for _,other in ipairs(dmhub.allTokens) do
        if other.valid and other.properties ~= nil and other.name == "Abyssal Rift" then
            result = result + 1
        end
    end
    return result
end

MonsterAI:RegisterMaliceAbility{
    id = "Demon Malice: Abyssal Rift",
    monsterGroups = demonGroup,
    abilities = {"Abyssal Rift"},
    description = "Spend 7 Malice to open two rifts beside the heroes, only when Malice is piling up and no rift is open.",
    score = function(self, ai, token, ability, context)
        if (context.malice or CharacterResource.GetMalice()) < abyssalRiftMinimumMalice then
            return nil, "Malice is better spent elsewhere"
        end
        if RiftsOnMap() > 0 then
            return nil, "a rift is already open"
        end
        local squares = RiftSquares(token, ability:GetNumTargets(token))
        if #squares == 0 then
            return nil, "no free space beside a hero"
        end
        return {score = 0.66, squares = #squares}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local squares = RiftSquares(token, ability:GetNumTargets(token))
        if #squares == 0 then
            return
        end
        Speak(ai, token, "rift")
        ai:ExecuteAbility(token, ability, squares, {sleep = abilityPause})
    end,
}
