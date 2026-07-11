local mod = dmhub.GetModLoading()

local function GenerateStandardStrikeScoreFunction(score)
    return function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability)
        if loc ~= nil then
            return {score = score, loc = loc}
        end
    end
end

local function GenerateStandardStrikeExecuteFunction()
    return function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end
end

MonsterAI:RegisterMove{
    id = "Charge and Free Strike",
    category = "Basic Strikes",
    description = "Move to melee range and use a free strike, charging if possible. This is a generic move that is used if no other good options are available.",
    abilities = {"Melee Free Strike"},
    score = GenerateStandardStrikeScoreFunction(0.2),
    execute = GenerateStandardStrikeExecuteFunction(),
}

MonsterAI:RegisterMove{
    id = "Ranged Free Strike",
    category = "Basic Strikes",
    description = "Move to ranged attack range and use a free strike. This is a generic move that is used if no other good options are available.",
    abilities = {"Ranged Free Strike"},
    score = GenerateStandardStrikeScoreFunction(0.2),
    execute = GenerateStandardStrikeExecuteFunction(),
}

local function GetKnockbackScoringFunction(token)
    local might = token.properties:GetAttribute("mgt"):Modifier()
    local oursize = token.properties:CreatureSizeWhenBeingForceMoved()
    return function(targetToken)
        if targetToken.properties:HasNamedCondition("Grabbed") then
            --don't knockback someone who we've grabbed.
            return -100
        end

        local size = targetToken.properties:CreatureSizeWhenBeingForceMoved()
        local result = 0.2 - targetToken.properties:Stability()*0.06 + might*0.06

        if oursize > size then
            result = result + 0.06
        end

        if targetToken.properties:CalculateNamedCustomAttribute("Cannot Be Force Moved") > 0 then
            --don't bother knockback on someone who can't be force moved.
            result = result - 100
        end

        return result
    end
end

MonsterAI:RegisterMove{
    id = "Knockback",
    category = "Maneuvers",
    description = "Maneuver: The generic knockback maneuver. Monsters prefer knocking back smaller and less stable targets. They won't knockback a grabbed target or a target that cannot be force moved, such as a restrained target.",
    abilities = {"Knockback"},
    score = function(self, ai, token, ability)
        --TODO: be selective about target, positioning, etc for knockback.
        local loc, score = ai:FindBestMoveToUseStrike(token, ability, GetKnockbackScoringFunction(token))
        if loc ~= nil then
            return {score = score, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)
        ai:Speech(token, {"Knockback!", "I'll give you a good shove"})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        local scorefn = GetKnockbackScoringFunction(token)
        table.sort(targets, function(a,b)
            return scorefn(a.token) > scorefn(b.token)
        end)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

local function GetGrabScoringFunction(token)
    local might = token.properties:GetAttribute("mgt"):Modifier()
    local stamina = token.properties:CurrentHitpoints()
    return function(targetToken)
        local staminaAdjustment = 0
        if stamina < 12 then
            --do not use since we are too low stamina.
            staminaAdjustment = -100
        elseif stamina < 20 then
            staminaAdjustment = -0.04
        end
        if targetToken.properties:HasNamedCondition("Grabbed") then
            --they are already grabbed.
            return -100
        end

        --the higher speed a target is the more valuable it is to grab it.
        local targetSpeed = targetToken.properties:CurrentMovementSpeed()
        return 0.08 + might*0.08 + (targetSpeed-6)*0.04 + staminaAdjustment
    end
end

MonsterAI:RegisterMove{
    id = "Grab",
    category = "Maneuvers",
    abilities = {"Grab"},
    description = "Grab: The generic grab maneuver. Only targets creatures that aren't already grabbed. Preferred by monsters with high might, and prefer to use on high speed targets. Monsters with low remaining stamina will avoid using grab, since an easily killed monster is not valuable for grabbing.",
    score = function(self, ai, token, ability)
        local loc, score = ai:FindBestMoveToUseStrike(token, ability, GetGrabScoringFunction(token))
        if loc ~= nil then
            return {score = score, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)
        ai:Speech(token, {"I'll get my hands on you!", "I'll grab you!", "You're not getting away!"})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Aid Attack",
    category = "Maneuvers",
    description = "Maneuver: The generic aid attack maneuver. Will usually be less preferred than knockback unless the creature is large or stable.",
    abilities = {"Aid Attack"},
    score = function(self, ai, token, ability)
        --TODO: be selective about target, positioning, etc for knockback.
        local targets = ai:FindValidTargetsOfStrike(token, ability, token.loc)
        --remove any targets that already have aid attack.
        if targets ~= nil then
            for i=#targets,1,-1 do
                if targets[i].token.properties._tmp_ai_aidAttack then
                    table.remove(targets, i)
                end
            end
        end

        if targets ~= nil and #targets > 0 then
            return {score = 0.1, loc = token.loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)
        ai:Speech(token, {"Aid Attack!", "Help me get them!"})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Spear Charge",
    category = "Main Actions",
    description = "Goblin Warrior spear charge action, uses charge to get in range.",
    monsters = {"Goblin Warrior"},
    abilities = {"Spear Charge"},
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability)
        if loc ~= nil then
            return {score = 1, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Bury the Point",
    category = "Main Actions",
    description = "Bury the Point Malice ability. This will be preferred over using Spear Charge if the target is reachable.",
    monsters = {"Goblin Warrior"},
    abilities = {"Bury the Point"},
    score = GenerateStandardStrikeScoreFunction(2),
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})

        ai.Sleep(1.0)
        ai:Speech(token, {"Bury the Point!", "I'll bury this spear in you!"})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end
}

MonsterAI:RegisterMove{
    id = "Shadow Chains",
    category = "Main Actions",
    description = "Shadow Chains Malice ability. This is the Goblin Assassin's preferred ability as long as they can hit three targets.",
    monsters = {"Goblin Pirate Assassin", "Goblin Assassin"},
    abilities = {"Shadow Chains"},
    score = function(self, ai, token, ability)
        print("AI:: SCORE CALLED WITH ABILITY", ability)
        local loc,score = ai:FindBestMoveToUseStrike(token, ability)
        print("AI:: BEST LOC TO USE STRIKE", loc)
        if loc ~= nil then
            return {score = score*0.4, loc = loc} --the scoring will make it more desirable than sword stab as long as there are three targets.
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(1.0)
        ai:Speech(token, "Shadow Chains!")

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Sword Stab",
    category = "Main Actions",
    description = "The Goblin Assassin's main ability. Used when Shadow Chains is not optimal or they can't afford the malice.",
    monsters = {"Goblin Pirate Assassin", "Goblin Assassin"},
    abilities = {"Sword Stab"},
    score = function(self, ai, token, ability)
        print("AI:: SCORE CALLED WITH ABILITY", ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability)
        print("AI:: BEST LOC TO USE STRIKE", loc)
        if loc ~= nil then
            return {score = 1, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})

        ai:Speech(token, {"Take this!", "Feel my blade!", "Die!"})
        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Hide in Concealment",
    category = "Maneuvers",
    description = "Move to an available concealed location and hide.",
    monsters = {"Goblin Pirate Assassin", "Goblin Assassin"},
    abilities = {"Hide"},
    score = function(self, ai, token, ability)
        if token.properties:HasNamedCondition("Hidden") then
            return nil
        end
        local loc = ai:FindReachableConcealment()
        if loc ~= nil then
            return {score = 0.5, loc = loc}
        end

        return nil
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, {"You can't catch me!", "Now you see me, now you don't!", "Try to find me!"})
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})

        ai:ExecuteAbility(token, ability, {})
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Drag",
    category = "Main Actions",
    monsters = {"Bugbear Channeler"},
    abilities = {"Shadow Drag"},
    description = "Bugbear Channeler's Shadow Drag ability, pulls targets maximizing collision damage if possible.",
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability)
        if loc ~= nil then
            local targets = ai:FindValidTargetsOfStrike(token, ability, loc)
            return {score = math.min(#targets,2), loc = loc}
        end

        return nil
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)
        ai:Speech(token, {"Shadow Drag!", "I'll pull you over here!"})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Twist Shape",
    category = "Main Actions",
    monsters = {"Bugbear Channeler"},
    abilities = {"Twist Shape"},
    description = "Bugbear Channeler's Twist Shape ability. This will be preferred over Shadow Drag if we can afford the malice.",
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability)
        if loc ~= nil then
            return {score = 2.5, loc = loc}
        end

        return nil
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)
        ai:Speech(token, {"I'll warp your very existence!", "Twist Shape!"})
        ai.Sleep(0.5)

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Blistering Element",
    category = "Main Actions",
    monsters = {"Bugbear Channeler"},
    abilities = {"Blistering Element"},
    description = "The Bugbear Channeler will run to the middle of a cluster of enemies to use this ability. It will be preferred over other abilities if it can hit at least three targets.",
    score = function(self, ai, token, ability)
        local loc, score = ai:FindBestMoveToUseBurst(token, ability)
        return {score = score*0.9, loc = loc} --this scoring will make it prefers to use drag unless it can get three heroes.
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)
        ai:Speech(token, {"Blistering Element!", "I'll end you all!"})
        ai.Sleep(0.5)

        ai:ExecuteAbility(token, ability)
    end,
}

MonsterAI:RegisterMove{
    id = "Two Shot",
    category = "Main Actions",
    monsters = {"Ryll"},
    abilities = {"Two Shot"},
    description = "Will position to hit two targets if possible.",
    score = GenerateStandardStrikeScoreFunction(1),
    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai.Sleep(0.5)
        if #targets >= 2 then
            ai:Speech(token, {"Two arrows notched!", "Both of you at once!"})
        else
            ai:Speech(token, {"Just one arrow today.", "Two stones, but only one bird."})
        end
        ai.Sleep(0.5)

        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Razor Claws",
    category = "Main Actions",
    monsters = {"Ghoul"},
    abilities = {"Razor Claws"},
    description = "Ghoul's preferred melee attack.",
    score = GenerateStandardStrikeScoreFunction(1),
    execute = GenerateStandardStrikeExecuteFunction(),
}

MonsterAI:RegisterMove{
    id = "Leap and Claw",
    category = "Maneuvers",
    monsters = {"Ghoul"},
    abilities = {"Leap", "Razor Claws"},
    description = "Ghouls will use their Leap ability to target size 1 creatures. Then they will move adjacent to them and use Razor Claws.",
    score = function(self, ai, token, leapAbility, razorClawsAbility)
        --synthesize an ability that looks like a charge to engage charge logic in calculations since a leap is very similar.
        local fakeAbility = DeepCopy(razorClawsAbility)
        fakeAbility:AddKeyword("Charge")
        fakeAbility.chargeDistanceOverride = 3
        local loc, score = ai:FindBestMoveToUseStrike(token, leapAbility, function(targetToken)
            --we only want to leap on targets small enough to knock prone.
            print("AI:: TARGET SIZE:", targetToken.tileSize)
            if targetToken.tileSize > 1 then
                return -1
            end

            return 2
        end)
        print("AI:: LEAP:", loc, score)
        if loc ~= nil and score ~= nil then
            return {score = score, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, leapAbility, razorClawsAbility)
        local fakeAbility = DeepCopy(razorClawsAbility)
        fakeAbility:AddKeyword("Charge")
        fakeAbility.chargeDistanceOverride = 3

        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        local targets = ai:FindValidTargetsOfStrike(token, fakeAbility, scoringInfo.loc)
        ai.Sleep(0.5)
        if targets == nil or #targets == 0 or targets[1].charge == nil then
            return
        end

        table.resize_array(targets, 1)

        local leapTargets = {
            {
                loc = targets[1].charge,
            }
        }

        targets[1].charge = nil

        --The leap ability prompts us to select a target to knock prone, set up the targets we will
        --use for this expected prompt.
        ai:SetTargetsForExpectedPrompt{
            casterid = token.charid,
            targets = targets,
            sleep = 0.5,
        }
        
        ai:ExecuteAbility(token, leapAbility, leapTargets)
        ai.Sleep(0.5)

        ai:ExecuteAbility(token, razorClawsAbility, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Clobber and Clutch",
    category = "Main Actions",
    monsters = {"Zombie"},
    abilities = {"Clobber and Clutch"},
    description = "Zombie's preferred melee attack.",
    score = GenerateStandardStrikeScoreFunction(1),
    execute = GenerateStandardStrikeExecuteFunction(),
}

MonsterAI:RegisterMove{
    id = "Zombie Dust",
    category = "Maneuvers",
    monsters = {"Zombie"},
    abilities = {"Zombie Dust"},
    description = "Maneuver: Zombies will use this if they can hit at least three enemies. They will use it after their main attack so they can attack before falling prone.",
    score = function(self, ai, token, ability)
        local loc, score = ai:FindBestMoveToUseBurst(token, ability)
        if loc == nil or score == nil or score < 3 then
            return nil
        end

        return {score = 0.8, loc = loc}
    end,

    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)

        ai:ExecuteAbility(token, ability)
    end,
}

MonsterAI:RegisterMove{
    id = "Bone Shards",
    category = "Main Actions",
    monsters = {"Skeleton"},
    abilities = {"Bone Shards"},
    description = "Skeleton's preferred attack.",
    score = GenerateStandardStrikeScoreFunction(1),
    execute = GenerateStandardStrikeExecuteFunction(),
}

MonsterAI:RegisterMove{
    id = "Bone Spur",
    category = "Maneuvers",
    monsters = {"Skeleton"},
    abilities = {"Bone Spur"},
    description = "Maneuver: Skeletons will use this if they can hit at least two enemies.",
    score = function(self, ai, token, ability)
        local loc, score = ai:FindBestMoveToUseBurst(token, ability)
        if loc == nil or score == nil or score < 2 then
            return nil
        end

        return {score = 0.8, loc = loc}
    end,

    execute = function(self, ai, token, scoringInfo, ability)
        local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(0.5)

        ai:ExecuteAbility(token, ability)
    end,
}

--------------------------------------------------------------------------------
-- Wallmaster.
--
-- The wallmaster is speed 0 and never moves; its whole kit works through wall
-- voxels created by its Living Labyrinth trait (tagged with wallcreator = its
-- charid, see AbilityBuildWall.lua). Living Labyrinth itself is a DM-driven
-- begin-round trigger card, not an AI move: wall placement is a strategic
-- choice made outside the AI turn loop.
--------------------------------------------------------------------------------

--true if this wall voxel token is the topmost cube of its tile's column; only
--top cubes are legal targets for Wall Slam / Dead End (Target.WallTop filter).
local function IsTopWallVoxel(wallToken)
    if wallToken.objectInstance == nil then
        return false
    end

    local loc = wallToken.loc
    local voxelFloor = game.currentMap:GetFloorFromLoc(loc)
    if voxelFloor == nil then
        return false
    end

    local voxels = voxelFloor:GetWallVoxelsAt(loc)
    if voxels == nil or #voxels == 0 then
        return false
    end

    return voxels[#voxels].objid == wallToken.objectInstance.objid
end

--own wall voxel tokens created by this creature's Living Labyrinth trait.
--Only the topmost cube per tile is returned (the targetable "square of wall").
local function FindWallmasterWalls(token)
    local result = {}
    for _,wallToken in ipairs(Encounter.GetTargetableObjectsWithKeyword("wallvoxel")) do
        if wallToken.valid and wallToken.properties:try_get("wallcreator") == token.charid and IsTopWallVoxel(wallToken) then
            result[#result+1] = wallToken
        end
    end
    return result
end

--enemies of token within 1 square of wallToken, best (lowest stamina fraction) first.
local function EnemiesAdjacentToWall(token, wallToken)
    local result = {}
    for _,tok in ipairs(dmhub.allTokens) do
        if tok.valid and (not tok:IsFriend(token)) and (not tok.properties:IsDead()) and wallToken:Distance(tok) <= 1 then
            result[#result+1] = tok
        end
    end

    table.sort(result, function(a,b)
        local afrac = a.properties:CurrentHitpoints() / math.max(1, a.properties.max_hitpoints)
        local bfrac = b.properties:CurrentHitpoints() / math.max(1, b.properties.max_hitpoints)
        return afrac < bfrac
    end)

    return result
end

MonsterAI:RegisterMove{
    id = "Wall Slam",
    category = "Main Actions",
    monsters = {"Wallmaster"},
    abilities = {"Wall Slam"},
    description = "Main action: topple squares of the wallmaster's Living Labyrinth wall onto adjacent enemies. Used when at least one enemy stands within 1 of one of its wall squares.",
    score = function(self, ai, token, ability)
        local range = ability:GetRange(token.properties)

        local slams = {}
        for _,wallToken in ipairs(FindWallmasterWalls(token)) do
            if token:Distance(wallToken) <= range then
                local enemies = EnemiesAdjacentToWall(token, wallToken)
                if #enemies > 0 then
                    slams[#slams+1] = { wall = wallToken, victim = enemies[1] }
                end
            end
        end

        if #slams == 0 then
            return nil
        end

        --prefer slams whose victims are most wounded.
        table.sort(slams, function(a,b)
            local afrac = a.victim.properties:CurrentHitpoints() / math.max(1, a.victim.properties.max_hitpoints)
            local bfrac = b.victim.properties:CurrentHitpoints() / math.max(1, b.victim.properties.max_hitpoints)
            return afrac < bfrac
        end)

        return {score = 1.5, loc = token.loc, slams = slams}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, {"The walls close in!", "Be crushed!"})
        ai.Sleep(0.5)

        --base two wall squares; the per-square victim picks are answered by the
        --"Wall Slam Topple" prompt handler below.
        local targets = {}
        for i,slam in ipairs(scoringInfo.slams) do
            if i <= 2 then
                targets[#targets+1] = { token = slam.wall }
            end
        end

        ai:ExecuteAbility(token, ability, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Dead End",
    category = "Maneuvers",
    monsters = {"Wallmaster"},
    abilities = {"Dead End"},
    description = "Maneuver: a Living Labyrinth wall square pushes an adjacent enemy and shifts into a square they vacate.",
    score = function(self, ai, token, ability)
        local range = ability:GetRange(token.properties)

        local best = nil
        for _,wallToken in ipairs(FindWallmasterWalls(token)) do
            if token:Distance(wallToken) <= range then
                local enemies = EnemiesAdjacentToWall(token, wallToken)
                if #enemies > 0 and best == nil then
                    best = { wall = wallToken, victim = enemies[1] }
                end
            end
        end

        if best == nil then
            return nil
        end

        return {score = 0.8, loc = token.loc, deadEnd = best}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, {"No way out.", "Dead end."})
        ai.Sleep(0.5)

        ai:ExecuteAbility(token, ability, { { token = scoringInfo.deadEnd.wall } })
    end,
}

MonsterAI:RegisterMove{
    id = "The Wall Sees All",
    category = "Maneuvers",
    monsters = {"Wallmaster"},
    abilities = {"The Wall Sees All"},
    description = "Malice: teleport to a wall within 10 squares and affix to it. Used when none of the wallmaster's own wall squares are within reach of its abilities.",
    score = function(self, ai, token, ability)
        --only worth relocating when the wallmaster has no useful wall in range:
        --no own wall square within 10 that has an enemy within 3 of it.
        for _,wallToken in ipairs(FindWallmasterWalls(token)) do
            if token:Distance(wallToken) <= 10 then
                for _,tok in ipairs(dmhub.allTokens) do
                    if tok.valid and (not tok:IsFriend(token)) and (not tok.properties:IsDead()) and wallToken:Distance(tok) <= 3 then
                        return nil
                    end
                end
            end
        end

        return {score = 0.6, loc = token.loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, {"The wall sees all.", "I am everywhere."})
        ai.Sleep(0.5)

        --the invoked standard Teleport prompts for a destination; there is no
        --AI handler for it, so the DM picks the wall to affix to.
        ai:ExecuteAbility(token, ability)
    end,
}
