local mod = dmhub.GetModLoading()

local undeadGroup = {"Undead"}

local movementPause = 0.6
local abilityPause = 1.0

local dreadMarchBaseCost = 7
local dreadMarchBaseUndead = 4

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject
        and token.properties ~= nil and not token.properties:IsDead()
end

local function IsMinion(token)
    return token.properties:try_get("minion", false) == true
end

local function LocKey(loc)
    return loc.xyfloorOnly.str
end

--Maps can hold props and bystanders who are not in the fight.
local function InCombat(token)
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return true
    end
    local initiativeid = InitiativeQueue.GetInitiativeId(token)
    return initiativeid ~= nil and queue.entries[initiativeid] ~= nil
end

local function HostileCreatures(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and not other:IsFriend(token) and InCombat(other) then
            result[#result+1] = other
        end
    end
    return result
end

local function FriendlyCreatures(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and other:IsFriend(token) and InCombat(other) then
            result[#result+1] = other
        end
    end
    return result
end

local function CanSee(token, target)
    return token:GetLineOfSight(target, token.properties:GetPierceWalls()) > 0
end

local function FindAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name then
            return ability
        end
    end
end

--Reading a creature's abilities copies every one of them, which is slow, so remember the answer for a few seconds.
local g_strikeProfiles = {time = 0, byCharid = {}}

--Every creature has a ranged free strike, so without the melee check melee undead would shoot from afar instead of closing in.
local function StrikeProfile(token)
    if dmhub.Time() - g_strikeProfiles.time > 5 then
        g_strikeProfiles = {time = dmhub.Time(), byCharid = {}}
    end
    local profile = g_strikeProfiles.byCharid[token.charid]
    if profile ~= nil then
        return profile
    end

    local freeStrikeReach = 1
    local melee = true
    local foundSignature = false
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == "Melee Free Strike" or ability.name == "Ranged Free Strike" then
            freeStrikeReach = math.max(freeStrikeReach, ability:GetRange(token.properties))
        elseif ability.categorization == "Signature Ability" and not foundSignature then
            foundSignature = true
            melee = ability:HasKeyword("Melee") and not ability:HasKeyword("Ranged")
        end
    end
    profile = {
        freeStrikeReach = freeStrikeReach,
        melee = melee,
        reach = cond(melee, 1, freeStrikeReach),
    }
    g_strikeProfiles.byCharid[token.charid] = profile
    return profile
end

local function NearestEnemyDistance(token, enemies)
    local nearest = math.huge
    for _,enemy in ipairs(enemies) do
        nearest = math.min(nearest, MonsterAI.TargetDistance(token, enemy))
    end
    return nearest
end

local function LandingIsFree(token, loc, reserved)
    if loc == nil or not loc.valid then
        return false
    end
    for _,occupied in ipairs(token:LocsOccupyingWhenAt(loc)) do
        if reserved[LocKey(occupied)] then
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

--Without this, the move and free strike prompts of marching undead go to the Director.
local function RunWithControlOf(ai, tokens, fn)
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
    return ok, err
end

local function MarchCandidates(token, ability, context)
    local enemies = {}
    for _,enemy in ipairs(context.enemyTokens or {}) do
        if LiveCreature(enemy) then
            enemies[#enemies+1] = enemy
        end
    end
    if #enemies == 0 then
        return {}, 0
    end

    local acting = {}
    for _,actor in ipairs(context.actingTokens or {}) do
        acting[actor.charid] = true
    end

    local candidates = {}
    local reachable = 0
    for _,undead in ipairs(FriendlyCreatures(token)) do
        --The march is refused if the caster cannot see every undead, so leave unseen ones out.
        if not undead.playerControlled
            and ability:TargetPassesFilter(token, undead, {})
            and (undead.charid == token.charid or CanSee(token, undead)) then
            local speed = undead.properties:CurrentMovementSpeed() or 0
            local nearest = NearestEnemyDistance(undead, enemies)
            --A rough straight-line guess; the move prompt finds the real path.
            local canReach = nearest <= speed + StrikeProfile(undead).freeStrikeReach
            local value = 0.1
            if canReach then
                reachable = reachable + 1
                value = cond(IsMinion(undead), 1, 1.5) + cond(acting[undead.charid], 0, 0.2)
            end
            candidates[#candidates+1] = {token = undead, value = value, nearest = nearest, canReach = canReach}
        end
    end
    table.sort(candidates, function(a, b)
        if a.value ~= b.value then
            return a.value > b.value
        end
        return a.nearest < b.nearest
    end)
    return candidates, reachable
end

--Captain Cryx (Horizon's Grave) has Malice features of her own. While she is in
--the fight and has not taken her turn yet this round, the shared undead features
--leave this much Malice for her, or Dread March would always spend it first.
local cryxMaliceReserve = 3
local cryxGroupName = "Undead Horizon's Grave"

local function InCryxGroup(token)
    local groupid = token.properties:try_get("groupid")
    if type(groupid) ~= "string" then
        return false
    end
    local group = dmhub.GetTable(MonsterGroup.tableName)[groupid]
    return group ~= nil and group.name == cryxGroupName
end

local function MaliceReservedForCryx()
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return 0
    end
    for _,tok in ipairs(dmhub.allTokens) do
        if LiveCreature(tok) and not tok.playerControlled and InCryxGroup(tok) then
            local initiativeid = InitiativeQueue.GetInitiativeId(tok)
            local entry = initiativeid ~= nil and queue.entries[initiativeid] or nil
            --an entry still due this round has not moved yet.
            if entry ~= nil and entry.round <= queue.round then
                return cryxMaliceReserve
            end
        end
    end
    return 0
end

--The Malice the shared undead features may spend.
local function SpendableMalice(context)
    local malice = context.malice or CharacterResource.GetMalice()
    return math.max(0, malice - MaliceReservedForCryx())
end

--True when the feature is affordable but only by spending what is kept for Cryx.
local function KeepingMaliceForCryx(cost, context)
    return SpendableMalice(context) < cost
end

--Undead moves registered elsewhere that spend Malice on their own turn (the
--Skeleton's Bone Spur, MonsterAIMonsters.lua) leave Cryx's share alone too.
local function KeepCryxReserveIn(moveid, cost)
    local move = MonsterAI.moves[moveid]
    if move == nil or move.keepsCryxReserve then
        return
    end
    local baseScore = move.score
    move.keepsCryxReserve = true
    move.score = function(self, ai, token, ...)
        if KeepingMaliceForCryx(cost, {}) then
            return nil, "keeping Malice for Captain Cryx"
        end
        return baseScore(self, ai, token, ...)
    end
end

KeepCryxReserveIn("Bone Spur", 2)

local function MarchPlan(token, ability, context)
    local candidates, reachable = MarchCandidates(token, ability, context)
    local extraMalice = math.max(0, SpendableMalice(context) - dreadMarchBaseCost)
    local count = math.max(dreadMarchBaseUndead, reachable)
    count = math.min(count, dreadMarchBaseUndead + extraMalice, #candidates)
    local chosen = {}
    local reaching = 0
    for i=1,count do
        chosen[#chosen+1] = candidates[i].token
        if candidates[i].canReach then
            reaching = reaching + 1
        end
    end
    return {
        undead = chosen,
        reaching = reaching,
        charges = math.max(0, count - dreadMarchBaseUndead),
    }
end

local function MarchIsViable(token, context)
    local march = FindAbility(token, "Dread March")
    if march == nil then
        return false
    end
    return MarchPlan(token, march, context).reaching >= 3
end

--While Dread March would be worth it, cheaper features only spend Malice the march does not need.
local function SavingForMarch(token, cost, context)
    return SpendableMalice(context) - cost < dreadMarchBaseCost and MarchIsViable(token, context)
end

local g_hordeRoundByEncounter = {}

--Every hero gets the effect, even one with undead beside them now: the effect checks again at the end of the round.
local function HordeTargets(token, ability, context)
    local result = {}
    for _,enemy in ipairs(context.enemyTokens or {}) do
        if LiveCreature(enemy) and enemy.properties:IsHero()
            and ability:TargetPassesFilter(token, enemy, {}) then
            result[#result+1] = enemy
        end
    end
    return result
end

--Keep this the same as the condition on the Ravenous Horde effect's trigger,
--so the AI only pays when zombies would rise.
local hordeVictimCheck = 'Count Nearby Enemies(1, "Undead") = 0'

local function ExecuteMapAbility(ai, caster, ability, targetTokens)
    local area = dmhub.CalculateShape{
        shape = "map",
        token = caster,
    }
    local targets = {}
    for _,target in ipairs(targetTokens) do
        targets[#targets+1] = {token = target}
    end
    ai:ExecuteAbility(caster, DeepCopy(ability), targets, {
        sleep = abilityPause,
        symbols = {targetArea = area},
        targetArea = area,
    })
end

MonsterAI:RegisterMaliceAbility{
    id = "Undead Malice: Ravenous Horde",
    monsterGroups = undeadGroup,
    abilities = {"Ravenous Horde"},
    description = "Spend 2 Malice to raise two rotting zombies next to each hero who has no undead beside them. Never two rounds in a row.",
    score = function(self, ai, token, ability, context)
        local queue = context.initiativeQueue
        local round = context.round or 0
        local lastRound = queue ~= nil and g_hordeRoundByEncounter[queue.guid] or nil
        if lastRound ~= nil and round - lastRound <= 1 then
            return nil, "used this round or last round"
        end
        --How many heroes would get zombies if the round ended now.
        local victims = 0
        for _,hero in ipairs(HordeTargets(token, ability, context)) do
            local result = ExecuteGoblinScript(hordeVictimCheck, hero.properties:LookupSymbol({}), 0, "Ravenous Horde AI")
            if GoblinScriptTrue(result) then
                victims = victims + 1
            end
        end
        if victims == 0 then
            return nil, "every hero already has an undead beside them"
        end
        if KeepingMaliceForCryx(2, context) then
            return nil, "keeping Malice for Captain Cryx"
        end
        if SavingForMarch(token, 2, context) then
            return nil, "saving Malice for Dread March"
        end
        return {score = math.min(0.95, 0.62 + 0.07*victims), heroes = victims}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = HordeTargets(token, ability, context)
        if #targets == 0 then
            return
        end
        local maliceBefore = CharacterResource.GetMalice()
        ExecuteMapAbility(ai, token, ability, targets)
        --A cancelled cast does not count, so Ravenous Horde can still be used next round.
        local queue = context.initiativeQueue
        if queue ~= nil and CharacterResource.GetMalice() < maliceBefore then
            g_hordeRoundByEncounter[queue.guid] = context.round or 0
        end
    end,
}

local g_march = nil

local function MarchMovePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if g_march == nil or not g_march.participants[casterToken.charid]
        or casterToken.playerControlled then
        return nil
    end
    local enemies = HostileCreatures(casterToken)
    if #enemies == 0 then
        return {targets = {}}
    end
    local profile = StrikeProfile(casterToken)
    local reach = profile.reach

    local canStrikeHere = false
    local adjacentHere = false
    for _,enemy in ipairs(enemies) do
        local dist = MonsterAI.TargetDistance(casterToken, enemy)
        if dist <= 1 then
            adjacentHere = true
        end
        if dist <= reach and CanSee(casterToken, enemy) then
            canStrikeHere = true
        end
    end
    if canStrikeHere and (profile.melee or not adjacentHere) then
        return {targets = {}}
    end

    local function NearestAt(loc)
        local target = enemies[1]
        local nearest = target:Distance(loc)
        for _,enemy in ipairs(enemies) do
            local dist = enemy:Distance(loc)
            if dist < nearest then
                nearest = dist
                target = enemy
            end
        end
        return target, nearest
    end

    local function SquareUtility(target, nearest)
        local utility = -nearest
        if nearest <= reach then
            utility = 10 + MonsterAI.TargetStaminaBias(target)
            if not profile.melee and nearest <= 1 then
                utility = utility - 3
            end
        end
        return utility
    end

    local here, hereDist = NearestAt(casterToken.loc)
    local hereUtility = SquareUtility(here, hereDist)

    local range = abilityClone:GetRange(casterToken.properties, symbols)
    local reserved = g_march.reserved
    local candidates = {}
    for _,info in pairs(casterToken:CalculatePathfindingArea(range*10, {})) do
        local loc = info.loc
        if loc ~= nil and LocKey(loc) ~= LocKey(casterToken.loc) and LandingIsFree(casterToken, loc, reserved) then
            local target, nearest = NearestAt(loc)
            candidates[#candidates+1] = {
                loc = loc,
                target = target,
                inReach = nearest <= reach,
                utility = SquareUtility(target, nearest) - (info.cost or 0)*0.002,
            }
        end
    end
    table.sort(candidates, function(a, b) return a.utility > b.utility end)

    local best = nil
    local approach = nil
    local checks = 0
    for _,candidate in ipairs(candidates) do
        if candidate.inReach then
            if checks < 10 then
                checks = checks + 1
                local usable = false
                ai:ExecuteWithTheoreticalMovementLoc(casterToken, candidate.loc, function()
                    usable = MonsterAI.TargetDistance(casterToken, candidate.target) <= reach
                        and CanSee(casterToken, candidate.target)
                end)
                if usable then
                    best = candidate
                    break
                end
            end
        elseif approach == nil then
            approach = candidate
            if checks >= 10 then
                break
            end
        end
    end
    best = best or approach
    if best == nil or best.utility <= hereUtility then
        return {targets = {}}
    end

    ReserveLanding(casterToken, best.loc, reserved)
    casterToken:MarkMovementArrow(best.loc, {straightline = false, ignorecreatures = false})
    MonsterAI.Sleep(movementPause)
    casterToken:ClearMovementArrow()
    return {targets = {{loc = best.loc}}}
end

--Each marching undead is asked to target itself before it moves; answer that for it.
local function MarchWrapperPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if g_march == nil or not g_march.participants[casterToken.charid]
        or abilityClone.targetType ~= "self" then
        return nil
    end
    return {targets = {{token = casterToken}}}
end

--Keep any handler already under this name (the Decrepit Skeleton's) and pass it every prompt that is not part of a march.
local function InstallMarchPrompt(name, marchHandler)
    local existing = MonsterAI.prompts[name]
    if existing ~= nil and existing.undeadMarch then
        return
    end
    MonsterAI:RegisterPrompt{
        id = existing ~= nil and existing.id or "Undead: Dread March",
        undeadMarch = true,
        prompts = {name},
        handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
            local result = marchHandler(ai, invokerToken, casterToken, abilityClone, symbols, options)
            if result == nil and existing ~= nil then
                return existing.handler(ai, invokerToken, casterToken, abilityClone, symbols, options)
            end
            return result
        end,
    }
end

local function RegisterMarchPrompts(tokens)
    for _,tok in ipairs(tokens) do
        local monsterType = tok.properties:try_get("monster_type", "")
        InstallMarchPrompt(monsterType .. ":Move Speed", MarchMovePrompt)
        InstallMarchPrompt(monsterType .. ":Invoked Ability", MarchWrapperPrompt)
    end
end

MonsterAI:RegisterMaliceAbility{
    id = "Undead Malice: Dread March",
    monsterGroups = undeadGroup,
    abilities = {"Dread March"},
    description = "Spend 7+ Malice to move four or more undead up to their speed into free strikes, when at least three of them can reach a hero.",
    score = function(self, ai, token, ability, context)
        if KeepingMaliceForCryx(dreadMarchBaseCost, context) then
            return nil, "keeping Malice for Captain Cryx"
        end
        local plan = MarchPlan(token, ability, context)
        if plan.reaching < 3 then
            return nil, string.format("only %d undead can reach a hero", plan.reaching)
        end
        --Not "targets": the decision log reads that field as a target list.
        return {
            score = math.min(0.95, 0.62 + 0.06*plan.reaching),
            marching = #plan.undead,
            reaching = plan.reaching,
            extraMalice = plan.charges,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        context.malice = CharacterResource.GetMalice()
        local plan = MarchPlan(token, ability, context)
        if #plan.undead == 0 then
            return
        end

        local targets = {}
        local participants = {}
        for _,undead in ipairs(plan.undead) do
            targets[#targets+1] = {token = undead}
            participants[undead.charid] = true
        end

        local promptTokens = {token}
        for _,undead in ipairs(plan.undead) do
            promptTokens[#promptTokens+1] = undead
        end
        RegisterMarchPrompts(promptTokens)

        --Its target count is "Charges + 4", which the AI would read as 4, so set it on a copy.
        local march = ability:MakeTemporaryClone()
        march.numTargets = tostring(#targets)
        local marched = false
        march.OnFinishCast = function(_, options)
            marched = not options.abort and not options.atexit
        end

        g_march = {participants = participants, reserved = {}}
        local ok, err = RunWithControlOf(ai, plan.undead, function()
            ai:ExecuteAbility(token, march, targets, {sleep = abilityPause})
        end)
        g_march = nil
        if not ok then
            error(err)
        end

        --AI casts only pay the base 7 Malice, so pay for the extra undead here.
        if marched and plan.charges > 0 then
            local malice = CharacterResource.GetMalice()
            CharacterResource.SetMalice(math.max(0, malice - plan.charges),
                string.format("Dread March: %d extra undead", plan.charges))
        end
    end,
}

--The arms reach one square past the 3x3 block, so anything within 2 of the centre gets grabbed, undead too.
local graspingReach = 2

--Where this encounter's arms already are, so a new patch is not wasted on enemies they already reach.
local g_graspingByEncounter = {}

local function ExistingArms(context)
    local queue = context.initiativeQueue
    if queue == nil then
        return {}
    end
    g_graspingByEncounter[queue.guid] = g_graspingByEncounter[queue.guid] or {}
    return g_graspingByEncounter[queue.guid]
end

local function GraspingPlan(token, context)
    local arms = ExistingArms(context)
    local enemies = {}
    for _,enemy in ipairs(context.enemyTokens or {}) do
        if LiveCreature(enemy) then
            local alreadyGrabbed = false
            for _,center in ipairs(arms) do
                if enemy:Distance(center) <= graspingReach then
                    alreadyGrabbed = true
                end
            end
            if not alreadyGrabbed then
                enemies[#enemies+1] = enemy
            end
        end
    end
    local allies = FriendlyCreatures(token)

    local seen = {}
    local best = nil
    for _,enemy in ipairs(enemies) do
        for dx=-graspingReach,graspingReach do
            for dy=-graspingReach,graspingReach do
                local center = enemy.loc:dir(dx, dy)
                local key = center.valid and LocKey(center) or nil
                if key ~= nil and not seen[key] then
                    seen[key] = true
                    local squares = {}
                    for sx=-1,1 do
                        for sy=-1,1 do
                            local square = center:dir(sx, sy)
                            if square.valid and square.isOnMap then
                                squares[#squares+1] = square
                            end
                        end
                    end
                    if #squares == 9 then
                        local caught = 0
                        local value = 0
                        for _,other in ipairs(enemies) do
                            if other:Distance(center) <= graspingReach then
                                caught = caught + 1
                                value = value + 1
                            end
                        end
                        for _,ally in ipairs(allies) do
                            if ally:Distance(center) <= graspingReach then
                                value = value - cond(IsMinion(ally), 0.6, 1)
                            end
                        end
                        if caught >= 2 and (best == nil or value > best.value) then
                            best = {center = center, squares = squares, caught = caught, value = value}
                        end
                    end
                end
            end
        end
    end
    return best
end

MonsterAI:RegisterMaliceAbility{
    id = "Undead Malice: The Grasping, the Hungry",
    monsterGroups = undeadGroup,
    abilities = {"The Grasping, the Hungry"},
    description = "Spend 5 Malice to raise grasping arms where at least two enemies, and few undead, would end their turns next to them.",
    score = function(self, ai, token, ability, context)
        local plan = GraspingPlan(token, context)
        if plan == nil or plan.value < 1.5 then
            return nil, "no spot catches two new enemies without catching undead"
        end
        if KeepingMaliceForCryx(5, context) then
            return nil, "keeping Malice for Captain Cryx"
        end
        if SavingForMarch(token, 5, context) then
            return nil, "saving Malice for Dread March"
        end
        return {
            score = math.min(0.9, 0.58 + 0.07*plan.value),
            caught = plan.caught,
            center = plan.center,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local plan = GraspingPlan(token, context)
        if plan == nil then
            return
        end
        local area = dmhub.CalculateShape{
            shape = "locations",
            token = token,
            locations = plan.squares,
            checklos = false,
        }
        local targets = {}
        for _,square in ipairs(plan.squares) do
            targets[#targets+1] = {loc = square}
        end
        local maliceBefore = CharacterResource.GetMalice()
        ai:ExecuteAbility(token, ability, targets, {
            sleep = abilityPause,
            symbols = {targetArea = area},
            targetArea = area,
        })
        if CharacterResource.GetMalice() < maliceBefore then
            local arms = ExistingArms(context)
            arms[#arms+1] = plan.center
        end
    end,
}

--------------------------------------------------------------------------------
-- Ghosts: the Ghost and Captain Cryx (Horizon's Grave), who shares its stat
-- block. Villain actions, Haunt, Shriek, the Paranormal Activity object pulls,
-- and Cryx's own Malice (Ghost Bolt and the two mast spins).
--------------------------------------------------------------------------------

local ghostMonsters = {"Ghost", "Captain Cryx"}
local cryxGroup = {"Undead Horizon's Grave"}

--Captain Cryx's lines. Kept together so they are easy to revise after playtests.
local cryxSpeech = {
    ["Paranormal Activity"] = {"Clear the decks!", "Mind the cargo, dogs!"},
    ["Spirited Away"] = {"Over the side with ye!", "Up the yardarm with ye!"},
    ["Awful Wail"] = {"The Horizon will never die!", "Lamagne's dogs, the lot of ye!"},
    ["Ghost Bolt"] = {"Fire!", "Fire the ballista!"},
    ["Spin the Mast"] = {"Spin her round, lads!", "All hands, brace!"},
    ["Haunt"] = {"Ye'll not pin me down!", "Ha! Too slow!"},
}

local function CryxSays(ai, token, key)
    if MonsterAI.AIMonsterType(token.properties) ~= "Captain Cryx" then
        return
    end
    local lines = cryxSpeech[key]
    if lines ~= nil then
        ai:Speech(token, lines)
        MonsterAI.Sleep(0.5)
    end
end

--Enemies a burst of this ability would catch from where the token stands.
local function BurstEnemies(token, ability)
    local range = ability:GetRange(token.properties)
    local result = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        if MonsterAI.TargetDistance(token, enemy) <= range and CanSee(token, enemy)
            and ability:TargetPassesFilter(token, enemy, {}) then
            result[#result+1] = enemy
        end
    end
    return result
end

local function IsWinded(token)
    local props = token.properties
    return props:CurrentHitpoints() <= props:MaxHitpoints()/2
end

local function NearestEnemyWithin(loc, enemies, distance)
    for _,enemy in ipairs(enemies) do
        if enemy:Distance(loc) <= distance then
            return enemy
        end
    end
    return nil
end

--Paranormal Activity's objects: in range, and with an enemy close enough to be pulled at.
local function ParanormalObjects(token, ability)
    local range = ability:GetRange(token.properties)
    local enemies = HostileCreatures(token)
    local result = {}
    for _,object in ipairs(dmhub.allObjectTokens) do
        if object.valid and MonsterAI.TargetDistance(token, object) <= range
            and ability:TargetPassesFilter(token, object, {})
            and NearestEnemyWithin(object.loc, enemies, 3) ~= nil then
            result[#result+1] = object
        end
    end
    return result
end

MonsterAI:RegisterVillainAction{
    id = "Ghost: Paranormal Activity",
    monsters = ghostMonsters,
    abilities = {"Paranormal Activity"},
    description = "Fling the nearby debris at the heroes when there are objects with a hero beside them.",
    score = function(self, ai, token, ability, context)
        local objects = ParanormalObjects(token, ability)
        if #objects == 0 then
            return nil, "no object in range has an enemy within 3 squares"
        end
        return {score = math.min(1, 0.45 + 0.2*#objects), objects = #objects}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,object in ipairs(ParanormalObjects(token, ability)) do
            targets[#targets+1] = {token = object}
        end
        if #targets == 0 then
            return
        end
        CryxSays(ai, token, "Paranormal Activity")
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Ghost: Spirited Away",
    monsters = ghostMonsters,
    abilities = {"Spirited Away"},
    description = "Levitate every enemy in the burst, best against a crowd.",
    score = function(self, ai, token, ability, context)
        local enemies = BurstEnemies(token, ability)
        if #enemies == 0 then
            return nil, "no enemy in the burst"
        end
        return {score = math.min(1, 0.4 + 0.15*#enemies), enemies = #enemies}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        CryxSays(ai, token, "Spirited Away")
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Ghost: Awful Wail",
    monsters = ghostMonsters,
    abilities = {"Awful Wail"},
    description = "Wail at every enemy in the burst; winded heroes may drop to 1 Stamina.",
    score = function(self, ai, token, ability, context)
        local enemies = BurstEnemies(token, ability)
        if #enemies == 0 then
            return nil, "no enemy in the burst"
        end
        local winded = 0
        for _,enemy in ipairs(enemies) do
            if IsWinded(enemy) then
                winded = winded + 1
            end
        end
        return {score = math.min(1, 0.45 + 0.15*#enemies + 0.05*winded), enemies = #enemies}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        CryxSays(ai, token, "Awful Wail")
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--Paranormal Activity pulls each object toward the nearest enemy within 3
--squares of it. The invoke's movement constraint already limits the squares,
--so the generic pull handler (which favours hitting enemies) picks among them.
local genericPullPrompt = MonsterAI.prompts["Pull!"]
MonsterAI:RegisterPrompt{
    id = "Ghost: Paranormal Activity Pull",
    prompts = {"Ghost:Forced Movement: Vertical Pull", "Captain Cryx:Forced Movement: Vertical Pull"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if genericPullPrompt ~= nil then
            return genericPullPrompt.handler(ai, invokerToken, casterToken, abilityClone, symbols, options)
        end
    end,
}

MonsterAI:RegisterTrigger{
    id = "Ghost: Shriek",
    monsters = ghostMonsters,
    abilities = {"Shriek"},
    triggers = {"Shriek"},
    description = "Always shriek at a striker: it halves the damage and hurts them.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

--Haunt: when the ghost starts next to an enemy, shift away (no opportunity
--attacks) to a square where its ranged signature still reaches enemies.
local hauntSignatureRange = 5

local function HauntDestination(token)
    local enemies = HostileCreatures(token)
    if NearestEnemyWithin(token.loc, enemies, 1) == nil then
        return nil
    end
    local speed = token.properties:CurrentMovementSpeed() or 0
    local best = nil
    for _,info in pairs(token:CalculatePathfindingArea(speed*10, {"shift"})) do
        local loc = info.loc
        if loc ~= nil and loc.valid and NearestEnemyWithin(loc, enemies, 1) == nil then
            local inReach = 0
            local nearest = math.huge
            for _,enemy in ipairs(enemies) do
                local dist = enemy:Distance(loc)
                nearest = math.min(nearest, dist)
                if dist <= hauntSignatureRange then
                    inReach = inReach + 1
                end
            end
            local value = math.min(inReach, 2) + math.min(nearest, 4)*0.05 - (info.cost or 0)*0.001
            if best == nil or value > best.value then
                best = {loc = loc, value = value, inReach = inReach}
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Ghost: Haunt Away",
    category = "Maneuvers",
    monsters = ghostMonsters,
    abilities = {"Haunt"},
    description = "Shift out of melee to a square that keeps enemies in range of the ghost's signature.",
    score = function(self, ai, token, ability)
        local plan = HauntDestination(token)
        if plan == nil then
            return nil, "not next to an enemy, or nowhere safe to shift"
        end
        return {score = cond(plan.inReach > 0, 0.9, 0.6), loc = plan.loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        CryxSays(ai, token, "Haunt")
        ai:SetTargetsForExpectedPrompt{
            casterid = token.charid,
            targets = {{loc = scoringInfo.loc}},
            sleep = movementPause,
        }
        ai:ExecuteAbility(token, ability, {{token = token}}, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Captain Cryx's Malice: Ghost Bolt and the mast spins.
--------------------------------------------------------------------------------

local boltLength = 10
local boltDirections = {{1,0}, {-1,0}, {0,1}, {0,-1}, {1,1}, {-1,-1}, {1,-1}, {-1,1}}

--Map bounds shrink to the encounter's region; a line must not run past them.
local function InMapBounds(loc)
    local dim = game.currentMap.dimensions
    return loc.x >= dim.x1 and loc.x < dim.x2 and loc.y >= dim.y1 and loc.y < dim.y2
end

--A 10-square line from origin, cut short by walls (line of sight) and the map bounds.
local function BoltShape(token, origin, dx, dy)
    local shape = dmhub.CalculateShape{
        shape = "line",
        token = token,
        locOverride = origin,
        targetPoint = token:PosAtLoc(origin:dir(dx*(boltLength + 2), dy*(boltLength + 2))),
        range = boltLength,
        radius = 1,
        checklos = true,
        altitude = 0,
    }
    local cutoff = math.huge
    for _,loc in ipairs(shape.locations) do
        if not InMapBounds(loc) then
            cutoff = math.min(cutoff, loc:DistanceInTiles(origin))
        end
    end
    local locs = {}
    for _,loc in ipairs(shape.locations) do
        if loc:DistanceInTiles(origin) < cutoff then
            locs[#locs+1] = loc
        end
    end
    return shape, locs
end

local function FarthestFrom(origin, locs)
    local best, bestDist = nil, -1
    for _,loc in ipairs(locs) do
        local dist = loc:DistanceInTiles(origin)
        if dist > bestDist then
            best, bestDist = loc, dist
        end
    end
    return best, bestDist
end

local function EnemiesOnLocs(token, ability, locs)
    local onLine = {}
    for _,loc in ipairs(locs) do
        onLine[LocKey(loc)] = true
    end
    local result = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        local hit = false
        for _,occupied in ipairs(enemy:LocsOccupyingWhenAt(enemy.loc)) do
            if onLine[LocKey(occupied)] then
                hit = true
            end
        end
        if hit and ability:TargetPassesFilter(token, enemy, {}) then
            result[#result+1] = enemy
        end
    end
    return result
end

--The bolt comes out of a wall: for each enemy and direction, walk back to the
--wall behind them, then fire 10 squares forward from there. Best = most enemies.
local function GhostBoltPlan(token, ability)
    local best = nil
    local seen = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        for _,d in ipairs(boltDirections) do
            local _, back = BoltShape(token, enemy.loc, -d[1], -d[2])
            local origin, dist = FarthestFrom(enemy.loc, back)
            --dist reaching the full length means no wall within reach behind this enemy.
            if origin ~= nil and dist < boltLength - 1 then
                local key = string.format("%s|%d|%d", LocKey(origin), d[1], d[2])
                if not seen[key] then
                    seen[key] = true
                    local shape, locs = BoltShape(token, origin, d[1], d[2])
                    local hits = EnemiesOnLocs(token, ability, locs)
                    if best == nil or #hits > #best.targets then
                        best = {shape = shape, locs = locs, targets = hits}
                    end
                end
            end
        end
    end
    return best
end

--How good a Malice area is for the number of enemies it catches. One enemy is
--enough (just over the 0.65 threshold): the other undead keep Malice back for these.
local function AreaMaliceScore(numEnemies)
    return math.min(0.92, 0.55 + 0.11*numEnemies)
end

MonsterAI:RegisterMaliceAbility{
    id = "Captain Cryx Malice: Ghost Bolt",
    monsterGroups = cryxGroup,
    abilities = {"Ghost Bolt"},
    description = "Fire a ballista bolt in a 10-square line from a wall through as many enemies as possible.",
    score = function(self, ai, token, ability, context)
        local plan = GhostBoltPlan(token, ability)
        if plan == nil or #plan.targets == 0 then
            return nil, "no wall-anchored line reaches an enemy"
        end
        return {score = AreaMaliceScore(#plan.targets) + 0.02, enemies = #plan.targets}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local plan = GhostBoltPlan(token, ability)
        if plan == nil or #plan.targets == 0 then
            return
        end
        plan.shape.locations = plan.locs
        local targets = {}
        for _,enemy in ipairs(plan.targets) do
            targets[#targets+1] = {token = enemy}
        end
        CryxSays(ai, token, "Ghost Bolt")
        ai:ExecuteAbility(token, ability, targets, {
            sleep = abilityPause,
            symbols = {targetArea = plan.shape},
            targetArea = plan.shape,
        })
    end,
}

--The mast an ability spins, named by the keyword its activateobjects macro uses.
local function MastKeyword(ability)
    for _,behavior in ipairs(ability.behaviors or {}) do
        if behavior.typeName == "ActivatedAbilityMacroBehavior" then
            local keyword = string.match(behavior:try_get("macro", ""), "activateobjects%s+([%w_]+)")
            if keyword ~= nil then
                return keyword
            end
        end
    end
    return nil
end

local function MastStanding(keyword)
    for _,obj in pairs(game.currentFloor.objects) do
        if obj.keywords ~= nil and obj.keywords[keyword] then
            return true
        end
    end
    return false
end

local function MastSpinPlan(token, ability)
    local keyword = MastKeyword(ability)
    if keyword ~= nil and not MastStanding(keyword) then
        return nil
    end
    local template = ability:try_get("areaTemplateObjectId")
    if template == nil or template == "" then
        return nil
    end
    local area = dmhub.CalculateShape{shape = "areatemplate", token = token, objectTemplate = template}
    if area == nil or #area.locations == 0 then
        return nil
    end
    local inZone = {}
    for _,loc in ipairs(area.locations) do
        inZone[LocKey(loc)] = true
    end
    local targets = {}
    for _,enemy in ipairs(HostileCreatures(token)) do
        --inZone is the area test; passing targetArea here makes template shapes reject everyone.
        if inZone[LocKey(enemy.loc)] and ability:TargetPassesFilter(token, enemy, {}) then
            targets[#targets+1] = enemy
        end
    end
    return {area = area, targets = targets}
end

local function RegisterMastSpin(abilityName)
    MonsterAI:RegisterMaliceAbility{
        id = "Captain Cryx Malice: " .. abilityName,
        monsterGroups = cryxGroup,
        abilities = {abilityName},
        description = "Spin a mast when enemies on the ground stand in its danger zone.",
        score = function(self, ai, token, ability, context)
            local plan = MastSpinPlan(token, ability)
            if plan == nil then
                return nil, "the mast is gone or has no danger zone"
            end
            if #plan.targets == 0 then
                return nil, "no enemy on the ground in the danger zone"
            end
            return {score = AreaMaliceScore(#plan.targets), enemies = #plan.targets}
        end,
        execute = function(self, ai, token, scoringInfo, ability, context)
            local plan = MastSpinPlan(token, ability)
            if plan == nil or #plan.targets == 0 then
                return
            end
            local targets = {}
            for _,enemy in ipairs(plan.targets) do
                targets[#targets+1] = {token = enemy}
            end
            CryxSays(ai, token, "Spin the Mast")
            ai:ExecuteAbility(token, ability, targets, {
                sleep = abilityPause,
                symbols = {targetArea = plan.area},
                targetArea = plan.area,
            })
        end,
    }
end

RegisterMastSpin("Spin the Mast (Front Mast)")
RegisterMastSpin("Spin The Mast (Back Mast)")

--------------------------------------------------------------------------------
-- Undead Malice: Paranormal Fling. Up to three loose objects near enemies are
-- lifted and slid at them; the generic slide handler aims each one.
--------------------------------------------------------------------------------

local flingObjects = 3

--Returns the objects to fling, plus counts of the objects passed over and why
--(for the decision log: which objects the AI thinks are loose, N5 playtest).
local function FlingObjects(token, ability)
    local enemies = HostileCreatures(token)
    local result = {}
    local skipped = {filter = 0, noEnemyNear = 0, notChecked = 0}
    for _,object in ipairs(dmhub.allObjectTokens) do
        if #result >= flingObjects then
            skipped.notChecked = skipped.notChecked + 1
        elseif object.valid then
            if not ability:TargetPassesFilter(token, object, {}) then
                skipped.filter = skipped.filter + 1
            elseif NearestEnemyWithin(object.loc, enemies, 3) == nil then
                skipped.noEnemyNear = skipped.noEnemyNear + 1
            else
                result[#result+1] = object
            end
        end
    end
    return result, skipped, enemies
end

--One log line per object: what it is, where it is, and the enemy it would fly at.
local function LogFlingObjects(ai, event, objects, enemies, extra)
    for i,object in ipairs(objects) do
        local enemy = NearestEnemyWithin(object.loc, enemies, 3)
        local fields = {
            object = string.format("%d/%d %s", i, #objects, MonsterAI.TokenLogName(object)),
            objectid = object.charid,
            loc = MonsterAI.LocLogName(object.loc),
            corpse = object.isCorpse,
            attackable = object.isAttackableObject,
            nearestEnemy = MonsterAI.TokenLogName(enemy),
            enemyDistance = enemy ~= nil and enemy:Distance(object.loc) or nil,
        }
        for key,value in pairs(extra or {}) do
            fields[key] = value
        end
        ai:LogDecision(event, fields)
    end
end

MonsterAI:RegisterMaliceAbility{
    id = "Undead Malice: Paranormal Fling",
    monsterGroups = undeadGroup,
    abilities = {"Paranormal Fling"},
    description = "Spend 3 Malice to fling up to three loose objects at nearby enemies, when at least two objects have a target. A full three-object fling goes ahead even while saving for Dread March.",
    score = function(self, ai, token, ability, context)
        local objects, skipped, enemies = FlingObjects(token, ability)
        ai:LogDecision("FLING CANDIDATES", {
            found = #objects,
            skippedByFilter = skipped.filter,
            skippedNoEnemyWithin3 = skipped.noEnemyNear,
            notChecked = skipped.notChecked,
            objectTokens = #dmhub.allObjectTokens,
        })
        LogFlingObjects(ai, "FLING CANDIDATE", objects, enemies)
        if #objects < 2 then
            return nil, "fewer than two loose objects near an enemy"
        end
        if KeepingMaliceForCryx(3, context) then
            return nil, "keeping Malice for Captain Cryx"
        end
        --A full fling (every object beside an enemy) is worth delaying Dread March for.
        local strong = #objects >= flingObjects
        if not strong and SavingForMarch(token, 3, context) then
            return nil, "saving Malice for Dread March"
        end
        return {score = cond(strong, 0.9, 0.75), objects = #objects}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local objects, _, enemies = FlingObjects(token, ability)
        local targets = {}
        local startLocs = {}
        for _,object in ipairs(objects) do
            targets[#targets+1] = {token = object}
            startLocs[object.charid] = MonsterAI.LocLogName(object.loc)
        end
        LogFlingObjects(ai, "FLING TARGET", objects, enemies)
        if #targets == 0 then
            return
        end
        local maliceBefore = CharacterResource.GetMalice()
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})

        --Where each object ended up: "moved=false" is a fling that did nothing.
        for i,object in ipairs(objects) do
            local endLoc = object.valid and MonsterAI.LocLogName(object.loc) or "gone"
            ai:LogDecision("FLING RESULT", {
                object = string.format("%d/%d %s", i, #objects, MonsterAI.TokenLogName(object)),
                objectid = object.charid,
                from = startLocs[object.charid],
                to = endLoc,
                moved = endLoc ~= startLocs[object.charid],
                maliceSpent = maliceBefore - CharacterResource.GetMalice(),
            })
        end
    end,
}
