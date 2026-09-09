local mod = dmhub.GetModLoading()

local shadowElves = {
    "Brush Stalker",
    "Shadow Elf Assassin",
    "Shadow Elf Cloak",
    "Shadow Elf Dusk Mage",
    "Shadow Elf Duskcaller",
    "Shadow Elf Eclipse",
    "Shadow Elf Knightfell",
    "Shadow Elf Luminator",
    "Shadow Elf Moondancer",
    "Shadow Elf Mournblade",
    "Shadow Elf Nightstrike",
    "Shadow Elf Noctis Mage",
    "Shadow Elf Panther",
    "Shadow Elf Shade",
    "Shadow Elf Sniper",
}

local fromTheShadowsSpeech = {
    "I shall summon thee from the shadows!",
    "I summon aid from the darkness!",
    "From shadow and thorn, answer my call!",
    "Darkness, send forth your hunter!",
    "Rise, stalker! The shadows call!",
}

local fromTheShadowsMoveSpeech = {
    "Move into position!",
    "Take your position!",
    "Close in!",
    "Advance through the shadows!",
}

local fromTheShadowsStrikeSpeech = {
    "Strike now!",
    "Now! Take them!",
    "Finish them!",
    "Attack!",
}

local fromTheShadowsStrikeSpeechByAncestry = {
    elf = {
        "Strike the elf now!",
        "Kill the filthy elf!",
        "Cut down the elf!",
    },
    dwarf = {
        "Get the dwarf!",
        "Break the dwarf!",
        "Bring down the dwarf!",
    },
    human = {
        "Strike the human!",
        "End the human!",
        "Cut down the human!",
    },
    orc = {
        "Get the orc!",
        "Bring down the orc!",
        "Strike the orc now!",
    },
    hakaan = {
        "Topple the hakaan!",
        "Bring down the giant!",
        "Strike the hakaan!",
    },
    polder = {
        "Catch the polder!",
        "Cut down the polder!",
        "Do not let the polder escape!",
    },
    revenant = {
        "Put the revenant back in the grave!",
        "Strike down the revenant!",
        "End the walking corpse!",
    },
}

local shadowElfCinematicSpeech = {
    ["Shadow Elf: Hide in Darkness"] = {
        "Let darkness take me.",
        "You saw nothing.",
        "The shadows close.",
    },
    ["Shadow Elf: Return to Darkness"] = {
        "Back to the dark.",
        "The light has seen enough.",
        "I return to shadow.",
    },
    ["Brush Stalker: Gore"] = {
        "Rrraugh!",
        "Grrrrraah!",
    },
    ["Brush Stalker: Reclamation"] = {
        "Rrraaaaaagh!",
        "GRAAAH!",
    },
    ["Shadow Elf Assassin: Lumina Assault"] = {
        "Your light betrays you.",
        "Marked for death.",
        "Now they all see you.",
    },
    ["Shadow Elf Assassin: Splitbow"] = {
        "One arrow. Many deaths.",
        "Stand together. Die together.",
        "The dark finds every heart.",
    },
    ["Shadow Elf Duskcaller: Night Knife"] = {
        "Night cuts deepest.",
        "A blade from darkness.",
        "You will not see the second.",
    },
    ["Shadow Elf Duskcaller: The Lay of Cor'thoroth"] = {
        "Cor'thoroth, veil us.",
        "Night, gather at my song.",
        "Let the Lay swallow the light.",
    },
    ["Shadow Elf Knightfell: Suffusing Strike"] = {
        "Your guard is an illusion.",
        "The dark seeps through steel.",
        "I strike from every shadow.",
    },
    ["Shadow Elf Moondancer: Crescent Sweep"] = {
        "Dance beneath the dying moon.",
        "The crescent claims you.",
        "Follow my blade.",
    },
    ["Shadow Elf Mournblade: Knife in the Dark"] = {
        "Grief has a sharp edge.",
        "This knife remembers the dark.",
        "Mourn the light.",
    },
    ["Shadow Elf Mournblade: Shadow Step"] = {
        "One shadow is every shadow.",
        "Distance means nothing in darkness.",
        "I step between heartbeats.",
    },
    ["Shadow Elf Luminator: Lumina Mark"] = {
        "The light marks you for death.",
        "Shine brightly. Die quickly.",
        "I paint the target.",
    },
    ["Shadow Elf Luminator: Mourning Till Dusk"] = {
        "Dusk restores what daylight stole.",
        "Rise. The night is not finished.",
        "Let mourning make you strong.",
    },
    ["Shadow Elf Noctis Mage: Blotting Bolt"] = {
        "Your aim dies with the light.",
        "Let darkness cloud your hand.",
        "Miss, and remember me.",
    },
    ["Shadow Elf Panther: Dusk Cleave"] = {
        "The dusk has claws.",
        "Two cuts. One shadow.",
        "I cleave the light from you.",
    },
    ["Shadow Elf Panther: Bladestorm"] = {
        "Stand close. It makes this easier.",
        "A storm of steel and shadow!",
        "Let every blade find flesh.",
    },
    ["Shadow Elf Shade: Gloom Dagger"] = {
        "A little gloom for your heart.",
        "You cannot parry a shadow.",
        "My dagger arrives before I do.",
    },
    ["Shadow Elf Shade: Duskfall"] = {
        "Dusk falls at my command.",
        "Hide us, merciful night.",
        "Let darkness shield my mentor.",
    },
    ["Shadow Elf Eclipse: Manifold Blade"] = {
        "One blade is never enough.",
        "Every shadow holds a knife.",
        "Choose which edge kills you.",
    },
    ["Shadow Elf Eclipse: Grasping Shadow"] = {
        "Come closer.",
        "The shadows have hands.",
        "There is no escape from the dark.",
    },
    ["Shadow Elf Eclipse: Cast Away All Hope"] = {
        "Hope is the first thing darkness devours.",
        "Cast away your courage.",
        "Despair, and be still.",
    },
    ["Shadow Elf Eclipse: Umbral Hunger"] = {
        "The darkness is hungry.",
        "Let the umbra feed.",
        "Night, devour them.",
    },
    ["Shadow Elf Malice: Watch Me Disappear"] = {
        "Disappear, children of shadow.",
        "Let the darkness hide us.",
        "Now you see us. Now you do not.",
    },
    ["Shadow Elf Malice: Extra Dimension"] = {
        "Bleed between worlds.",
        "The manifold cuts deeper.",
        "One wound, two dimensions.",
    },
    ["Shadow Elf Malice: Home Is Where the Hurt Is"] = {
        "Let Equinox consume this battlefield.",
        "Two worlds become one.",
        "Behold the manifold of our home.",
    },
}

local shadowElfCinematicPause = 1.0
local shadowElfSpeechPause = 0.5
local fromTheShadowsPause = shadowElfCinematicPause

local function ShadowElfCinematicSpeech(ai, token, moveid)
    local lines = shadowElfCinematicSpeech[moveid]
    if lines ~= nil then
        ai:Speech(token, lines)
        ai.Sleep(shadowElfSpeechPause)
    end
end

local function HeroMatchesAncestry(hero, ancestryName)
    if hero == nil or not hero.valid or hero.properties == nil
        or not hero.properties:IsHero() or hero.properties:IsDead() then
        return false
    end

    local ok, ancestry = pcall(function()
        return string.lower(hero.properties:RaceOrMonsterType())
    end)
    return ok and string.find(ancestry, ancestryName, 1, true) ~= nil
end

local function FromTheShadowsStrikeSpeech(target)
    if target ~= nil and target.properties ~= nil and target.properties:IsHero() then
        local ok, ancestry = pcall(function()
            return string.lower(target.properties:RaceOrMonsterType())
        end)
        if ok then
            for ancestryName,lines in pairs(fromTheShadowsStrikeSpeechByAncestry) do
                if string.find(ancestry, ancestryName, 1, true) ~= nil then
                    local matchingHeroes = 0
                    for _,hero in pairs(dmhub.allTokens) do
                        if HeroMatchesAncestry(hero, ancestryName) then
                            matchingHeroes = matchingHeroes + 1
                        end
                    end
                    if matchingHeroes == 1 then
                        return lines
                    end
                    return fromTheShadowsStrikeSpeech
                end
            end
        end
    end

    return fromTheShadowsStrikeSpeech
end

local function FindAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name then
            return ability
        end
    end
end

local function FindAbilityByGuid(token, guid)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.guid == guid then
            return ability
        end
    end
end

local function LocationProfile(token, loc)
    local lookup = GenerateSymbols(Loc.Create(loc))
    local environment = lookup("environment")
    local result = {
        darkness = environment ~= nil and environment:Has("Darkness"),
        sunlight = environment ~= nil and environment:Has("Sunlight"),
        concealed = lookup("concealment") == true,
    }

    if result.darkness then
        result.score = 3
    elseif result.sunlight then
        result.score = cond(result.concealed, 0, -1)
    elseif result.concealed then
        result.score = 2
    else
        result.score = 1
    end

    return result
end

local function FindBetterDefensiveLoc(ai, token)
    local current = LocationProfile(token, token.loc)
    local bestLoc = nil
    local bestProfile = current
    local bestCost = nil

    for _,info in pairs(ai.paths) do
        local profile = LocationProfile(token, info.loc)
        if profile.score > bestProfile.score
            or (bestLoc ~= nil and profile.score == bestProfile.score and info.cost < bestCost) then
            bestLoc = info.loc
            bestProfile = profile
            bestCost = info.cost
        end
    end

    return bestLoc, bestProfile
end

local function FindHideLoc(ai, token)
    local current = LocationProfile(token, token.loc)
    if current.concealed and not current.sunlight then
        return token.loc
    end

    local bestLoc = nil
    local bestScore = nil
    local bestCost = nil
    for _,info in pairs(ai.paths) do
        local profile = LocationProfile(token, info.loc)
        if profile.concealed and not profile.sunlight then
            if bestScore == nil or profile.score > bestScore
                or (profile.score == bestScore and info.cost < bestCost) then
                bestLoc = info.loc
                bestScore = profile.score
                bestCost = info.cost
            end
        end
    end

    return bestLoc
end

local function GenerateStandardStrikeScoreFunction(score)
    return function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability)
        if loc ~= nil then
            return {score = score, loc = loc}
        end
    end
end

local function MoveCinematically(ai, token, loc)
    local moving = loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc)
    ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
    ai.Sleep(cond(moving, shadowElfCinematicPause, shadowElfSpeechPause))
end

local function GenerateStandardStrikeExecuteFunction(moveid)
    return function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ShadowElfCinematicSpeech(ai, token, moveid)

        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets, {sleep = shadowElfCinematicPause})
    end
end

local function RegisterStandardStrike(id, monsterType, abilityName, score, description)
    MonsterAI:RegisterMove{
        id = id,
        category = "Main Actions",
        monsters = {monsterType},
        abilities = {abilityName},
        description = description,
        score = GenerateStandardStrikeScoreFunction(score or 1),
        execute = GenerateStandardStrikeExecuteFunction(id),
    }
end

local function TokensInArea(casterToken, ability, area, symbols, additionalFilter)
    local result = {}
    symbols = symbols or {}
    symbols.targetArea = area
    for _,tok in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if tok.valid and ability:TargetPassesFilter(casterToken, tok, symbols)
            and (additionalFilter == nil or additionalFilter(tok)) then
            result[#result+1] = {token = tok}
        end
    end
    return result
end

local function BuildCubeArea(token, ability, center, mode)
    local symbols = {mode = mode or 1}
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(center),
        token = token,
        range = ability:GetRange(token.properties, symbols),
        radius = ability:GetRadius(token.properties, symbols),
        checklos = true,
        altitude = center.altitude * dmhub.unitsPerSquare,
    }
end

local function ExecuteAreaAbility(ai, token, ability, area, targets, options)
    options = options or {}
    options.sleep = options.sleep or shadowElfCinematicPause
    options.symbols = options.symbols or {}
    options.symbols.targetArea = area
    options.targetArea = area

    -- ExecuteAbility resolves modes on its temporary clone. Isolate that write
    -- from the instance cached in ai.abilities.
    local abilityClone = DeepCopy(ability)

    ai:ExecuteAbility(token, abilityClone, targets, options)
    area:Destroy()
end

local function OffsetLoc(loc, dx, dy)
    local result = loc
    local horizontal = cond(dx >= 0, "east", "west")
    local vertical = cond(dy >= 0, "north", "south")
    for i=1,math.abs(dx) do
        result = result[horizontal]
    end
    for i=1,math.abs(dy) do
        result = result[vertical]
    end
    return result
end

local lineDirections = {
    {1, 0}, {-1, 0}, {0, 1}, {0, -1},
    {1, 1}, {1, -1}, {-1, 1}, {-1, -1},
}

local function FindBestSplitbowLine(ai, token, ability)
    local symbols = {mode = 1}
    local lineLength = ability:GetRange(token.properties, symbols)
    local lineDistance = ability:GetLineDistance(token.properties, symbols)
    local lineWidth = ability:GetRadius(token.properties, symbols)
    local best = nil

    for _,enemy in ipairs(ai.enemyTokens) do
        local startLoc = enemy.loc
        if token:Distance(startLoc) <= lineDistance then
            for _,direction in ipairs(lineDirections) do
                local endLoc = OffsetLoc(startLoc, direction[1]*lineLength, direction[2]*lineLength)
                if endLoc.valid and endLoc.isOnMap then
                    local area = dmhub.CalculateShape{
                        shape = "line",
                        targetPoint = token:PosAtLoc(endLoc),
                        token = token,
                        range = lineLength,
                        radius = lineWidth,
                        locOverride = startLoc,
                        checklos = true,
                    }
                    local targets = TokensInArea(token, ability, area, symbols)
                    if best == nil or #targets > best.numTargets then
                        best = {
                            startLoc = startLoc,
                            endLoc = endLoc,
                            numTargets = #targets,
                        }
                    end
                    area:Destroy()
                end
            end
        end
    end

    return best
end

local function ExecuteSplitbow(ai, token, ability, info)
    local symbols = {mode = 1}
    local area = dmhub.CalculateShape{
        shape = "line",
        targetPoint = token:PosAtLoc(info.endLoc),
        token = token,
        range = ability:GetRange(token.properties, symbols),
        radius = ability:GetRadius(token.properties, symbols),
        locOverride = info.startLoc,
        checklos = true,
    }
    local targets = TokensInArea(token, ability, area, symbols)
    ExecuteAreaAbility(ai, token, ability, area, targets, {symbols = symbols})
end

local function IsEmptyFor(token, loc)
    for _,other in ipairs(dmhub.GetTokensAtLoc(loc) or {}) do
        if other.valid and other.charid ~= token.charid then
            return false
        end
    end
    return true
end

local function DistanceFromNearestEnemy(token, loc)
    local result = 999
    for _,other in ipairs(dmhub.allTokens) do
        if other.valid and other.properties ~= nil and (not other:IsFriend(token))
            and (not other.properties:IsDead()) then
            result = math.min(result, other:Distance(loc))
        end
    end
    return result
end

local function FindDarkTeleportLoc(token, ability, preferClose)
    local range = ability:GetRange(token.properties)
    local area = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = token,
        range = range,
        radius = range,
        checklos = false,
    }
    local predicate = ability:TargetLocPassesFilterPredicate(token, {}) or function() return true end
    local bestLoc = nil
    local bestScore = nil

    for _,loc in ipairs(area.locations) do
        local profile = LocationProfile(token, loc)
        if profile.darkness and IsEmptyFor(token, loc) and predicate(loc) then
            local distance = DistanceFromNearestEnemy(token, loc)
            local score = cond(preferClose, -distance, distance)
            if bestScore == nil or score > bestScore then
                bestLoc = loc
                bestScore = score
            end
        end
    end

    area:Destroy()
    return bestLoc
end

local function FindPromptTargets(casterToken, ability, symbols, filter)
    local result = {}
    for _,tok in ipairs(dmhub.allTokens) do
        if tok.valid and tok.properties ~= nil
            and ability:TargetPassesFilter(casterToken, tok, symbols)
            and (filter == nil or filter(tok)) then
            result[#result+1] = {token = tok}
        end
    end

    table.sort(result, function(a, b)
        local ahp = a.token.properties:CurrentHitpoints() / math.max(1, a.token.properties.max_hitpoints)
        local bhp = b.token.properties:CurrentHitpoints() / math.max(1, b.token.properties.max_hitpoints)
        return ahp < bhp
    end)

    table.resize_array(result, ability:GetNumTargets(casterToken, symbols))
    return result
end

--------------------------------------------------------------------------------
-- Start-of-turn Malice abilities.
--------------------------------------------------------------------------------

local watchMeDisappearEffectId = "df02bea3-fe93-4377-b839-fe7fef78164b"
local watchMeDisappearFreeHideGuid = "f08403cd-f185-4d02-8cae-3153e37f6aff"
local extraDimensionEffectId = "a3b002ad-b9fc-4974-8dd8-c5bf5313adde"
local homeIsWhereTheHurtIsEffectId = "2c6af670-18b3-4708-994f-c52b994e74c2"

local function HasOngoingEffect(token, ongoingEffectId)
    if token == nil or not token.valid or token.properties == nil then
        return false
    end

    for _,effect in ipairs(token.properties:ActiveOngoingEffects()) do
        if effect.ongoingEffectid == ongoingEffectId then
            return true
        end
    end
    return false
end

local function AnyGroupTokenHasEffect(tokens, ongoingEffectId)
    for _,token in ipairs(tokens) do
        if HasOngoingEffect(token, ongoingEffectId) then
            return true
        end
    end
    return false
end

local function IsShadowElfGroupToken(token)
    if token == nil or not token.valid or token.properties == nil or token.properties:IsDead() then
        return false
    end

    local group = token.properties:MonsterGroup()
    return group ~= nil and group.name == "Shadow Elf"
end

local function HasAffordableStrike(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.categorization ~= "Malice" and ability:HasKeyword("Strike") and ability:CanAfford(token) then
            return true
        end
    end
    return false
end

local function HasLowIntuition(token)
    local ok, intuition = pcall(function()
        return token.properties:GetAttribute("inu"):Value()
    end)
    return ok and type(intuition) == "number" and intuition < 2
end

MonsterAI:RegisterMaliceAbility{
    id = "Shadow Elf Malice: Watch Me Disappear",
    monsterGroups = {"Shadow Elf"},
    abilities = {"Watch Me Disappear"},
    description = "At the start of a Shadow Elf turn, spend 3 Malice when concealed actors can immediately attempt to hide for free.",
    score = function(self, ai, token, ability, context)
        if AnyGroupTokenHasEffect(context.groupTokens, watchMeDisappearEffectId) then
            return nil
        end

        local beneficiaries = {}
        for _,actor in ipairs(context.groupTokens) do
            if not actor.properties:HasNamedCondition("Hidden")
                and LocationProfile(actor, actor.loc).concealed then
                beneficiaries[#beneficiaries+1] = actor
            end
        end

        if #beneficiaries == 0 then
            return nil
        end

        return {
            score = math.min(1, 0.55 + #beneficiaries*0.15),
            beneficiaries = beneficiaries,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = shadowElfCinematicPause})

        for _,actor in ipairs(scoringInfo.beneficiaries) do
            if actor.valid and actor.properties ~= nil and not actor.properties:IsDead()
                and not actor.properties:HasNamedCondition("Hidden")
                and LocationProfile(actor, actor.loc).concealed then
                local freeHide = FindAbilityByGuid(actor, watchMeDisappearFreeHideGuid)
                if freeHide ~= nil and freeHide:CanAfford(actor) then
                    local ok, err = ai:RunWithTokenControl(actor, function()
                        ai:ExecuteAbility(actor, freeHide, {}, {sleep = shadowElfCinematicPause})
                    end)
                    if not ok then
                        print("AI:: Watch Me Disappear free Hide failed:", err)
                    end
                end
            end
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Shadow Elf Malice: Extra Dimension",
    monsterGroups = {"Shadow Elf"},
    abilities = {"Extra Dimension"},
    description = "At the start of a Shadow Elf turn, spend 5 Malice when acting strikers can exploit enemies with Intuition lower than 2.",
    score = function(self, ai, token, ability, context)
        if AnyGroupTokenHasEffect(context.groupTokens, extraDimensionEffectId) then
            return nil
        end

        local numStrikers = 0
        for _,actor in ipairs(context.groupTokens) do
            if HasAffordableStrike(actor) then
                numStrikers = numStrikers + 1
            end
        end

        local numLowIntuitionTargets = 0
        for _,enemy in ipairs(context.enemyTokens) do
            if enemy.valid and enemy.properties ~= nil and not enemy.properties:IsDead()
                and HasLowIntuition(enemy) then
                numLowIntuitionTargets = numLowIntuitionTargets + 1
            end
        end

        if numStrikers == 0 or numLowIntuitionTargets == 0 then
            return nil
        end

        return {
            score = math.min(1, 0.35 + math.min(3, numStrikers)*0.15
                + math.min(2, numLowIntuitionTargets)*0.15),
            numLowIntuitionTargets = numLowIntuitionTargets,
            numStrikers = numStrikers,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = shadowElfCinematicPause})
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Shadow Elf Malice: Home Is Where the Hurt Is",
    monsterGroups = {"Shadow Elf"},
    abilities = {"Home Is Where the Hurt Is"},
    description = "At the start of an early Shadow Elf turn, spend 10 Malice when the encounter-long potency benefit outweighs losing Of the Umbra.",
    minimumScore = 0.7,
    score = function(self, ai, token, ability, context)
        if context.round ~= nil and context.round > 3 then
            return nil
        end

        local liveShadowElves = {}
        local numInDarkness = 0
        for _,ally in ipairs(context.allyTokens) do
            if IsShadowElfGroupToken(ally) then
                liveShadowElves[#liveShadowElves+1] = ally
                if LocationProfile(ally, ally.loc).darkness then
                    numInDarkness = numInDarkness + 1
                end
            end
        end

        if #liveShadowElves < 3 or #context.enemyTokens < 2
            or AnyGroupTokenHasEffect(liveShadowElves, homeIsWhereTheHurtIsEffectId) then
            return nil
        end

        local nonDarknessRatio = (#liveShadowElves - numInDarkness) / #liveShadowElves
        local roundPenalty = math.max(0, (context.round or 1) - 1)*0.1
        local score = 0.25
            + math.min(5, #liveShadowElves)*0.08
            + math.min(5, #context.enemyTokens)*0.04
            + (nonDarknessRatio - 0.5)*0.4
            - roundPenalty

        return {
            score = math.max(0, math.min(1, score)),
            liveShadowElves = #liveShadowElves,
            numInDarkness = numInDarkness,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = shadowElfCinematicPause})
    end,
}

--------------------------------------------------------------------------------
-- Shared shadow elf positioning.
--------------------------------------------------------------------------------

MonsterAI:RegisterTactic{
    id = "Shadow Elf: Of the Umbra Positioning",
    monsters = shadowElves,
    description = "Prefer attack positions in darkness or concealment and avoid ending an attack in sunlight. Attacking always remains more important than this preference.",
    score = function(self, token, tokenLoc, enemy, ability)
        local profile = LocationProfile(token, tokenLoc)
        if profile.darkness then
            return 2
        elseif profile.sunlight then
            return -2
        elseif profile.concealed then
            return 1
        end
        return 0
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Elf: Hide in Darkness",
    category = "Maneuvers",
    monsters = shadowElves,
    abilities = {"Hide"},
    description = "After attacking, move to a concealed non-sunlit location and hide when possible.",
    score = function(self, ai, token, ability)
        if token.properties:HasNamedCondition("Hidden") then
            return nil
        end
        local loc = FindHideLoc(ai, token)
        if loc ~= nil then
            return {score = 0.45, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, {}, {sleep = shadowElfCinematicPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Elf: Return to Darkness",
    category = "Tactics",
    monsters = shadowElves,
    abilities = {},
    description = "After all attacks and useful maneuvers, end the turn in darkness, concealment, or at least outside sunlight when reachable.",
    score = function(self, ai, token)
        local loc = FindBetterDefensiveLoc(ai, token)
        if loc ~= nil then
            return {score = 0.1, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo)
        ShadowElfCinematicSpeech(ai, token, self.id)
        MoveCinematically(ai, token, scoringInfo.loc)
    end,
}

--------------------------------------------------------------------------------
-- Main actions.
--------------------------------------------------------------------------------

RegisterStandardStrike(
    "Brush Stalker: Gore",
    "Brush Stalker",
    "Gore",
    1,
    "Charge into melee and gore up to two targets.")

RegisterStandardStrike(
    "Shadow Elf Assassin: Lumina Assault",
    "Shadow Elf Assassin",
    "Lumina Assault",
    1,
    "Mark a target with Lumina Assault, enabling the next attack to exploit a double edge.")

RegisterStandardStrike(
    "Shadow Elf Duskcaller: Night Knife",
    "Shadow Elf Duskcaller",
    "Night Knife",
    1,
    "Use Night Knife, gaining its second target automatically while concealed.")

RegisterStandardStrike(
    "Shadow Elf Knightfell: Suffusing Strike",
    "Shadow Elf Knightfell",
    "Suffusing Strike",
    1,
    "Use Suffusing Strike from a protected ranged position.")

RegisterStandardStrike(
    "Shadow Elf Moondancer: Crescent Sweep",
    "Shadow Elf Moondancer",
    "Crescent Sweep",
    1,
    "Charge into melee with Crescent Sweep.")

RegisterStandardStrike(
    "Shadow Elf Mournblade: Knife in the Dark",
    "Shadow Elf Mournblade",
    "Knife in the Dark",
    1,
    "Use Knife in the Dark as the mournblade's preferred attack.")

RegisterStandardStrike(
    "Shadow Elf Luminator: Lumina Mark",
    "Shadow Elf Luminator",
    "Lumina Mark",
    1,
    "Mark an enemy so the next strike against them deals extra damage.")

RegisterStandardStrike(
    "Shadow Elf Noctis Mage: Blotting Bolt",
    "Shadow Elf Noctis Mage",
    "Blotting Bolt",
    1,
    "Use Blotting Bolt to hinder the target's next attack.")

RegisterStandardStrike(
    "Shadow Elf Panther: Dusk Cleave",
    "Shadow Elf Panther",
    "Dusk Cleave",
    1,
    "Use Dusk Cleave and take its follow-up free strike when another target is adjacent.")

RegisterStandardStrike(
    "Shadow Elf Shade: Gloom Dagger",
    "Shadow Elf Shade",
    "Gloom Dagger",
    1,
    "Use the shade's Gloom Dagger from melee or range.")

RegisterStandardStrike(
    "Shadow Elf Eclipse: Manifold Blade",
    "Shadow Elf Eclipse",
    "Manifold Blade",
    1,
    "Use Manifold Blade against up to two adjacent enemies.")

MonsterAI:RegisterMove{
    id = "Brush Stalker: Reclamation",
    category = "Main Actions",
    monsters = {"Brush Stalker"},
    abilities = {"Reclamation"},
    description = "Spend Malice on Reclamation when its burst can damage and weaken at least two enemies.",
    score = function(self, ai, token, ability)
        local loc, score = ai:FindBestMoveToUseBurst(token, ability)
        if loc ~= nil and score ~= nil and score >= 2 then
            return {score = 1.8, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = shadowElfCinematicPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Elf Assassin: Splitbow",
    category = "Main Actions",
    monsters = {"Shadow Elf Assassin"},
    abilities = {"Splitbow"},
    description = "Spend Malice on Splitbow when a 4-by-1 line can catch at least two enemies.",
    score = function(self, ai, token, ability)
        local line = FindBestSplitbowLine(ai, token, ability)
        if line ~= nil and line.numTargets >= 2 then
            return {score = 1.8, line = line}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ExecuteSplitbow(ai, token, ability, scoringInfo.line)
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Elf Luminator: Mourning Till Dusk",
    category = "Main Actions",
    monsters = {"Shadow Elf Luminator"},
    abilities = {"Mourning Till Dusk"},
    description = "Spend Malice to heal a worthwhile cluster of injured allies and grant their next strikes an edge.",
    score = function(self, ai, token, ability)
        local loc, healingValue = ai:FindBestMoveToUseBurst(token, ability, function(target)
            local missing = math.max(0, target.properties.max_hitpoints - target.properties:CurrentHitpoints())
            return math.min(1, missing / 12)
        end)
        if loc ~= nil and healingValue ~= nil and healingValue >= 1 then
            return {score = 1.7, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = shadowElfCinematicPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Elf Panther: Bladestorm",
    category = "Main Actions",
    monsters = {"Shadow Elf Panther"},
    abilities = {"Bladestorm"},
    description = "Spend Malice on Bladestorm when its burst can hit at least two enemies.",
    score = function(self, ai, token, ability)
        local loc, score = ai:FindBestMoveToUseBurst(token, ability)
        if loc ~= nil and score ~= nil and score >= 2 then
            return {score = 1.8, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = shadowElfCinematicPause})
    end,
}

--------------------------------------------------------------------------------
-- Maneuvers and darkness creation.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Shadow Elf Duskcaller: The Lay of Cor'thoroth",
    category = "Maneuvers",
    monsters = {"Shadow Elf Duskcaller"},
    abilities = {"The Lay of Cor'thoroth", "Night Knife"},
    description = "Move into Night Knife range, surround the duskcaller with darkness, then attack on the next AI action cycle.",
    score = function(self, ai, token, layAbility, knifeAbility)
        if LocationProfile(token, token.loc).darkness then
            return nil
        end
        local loc = ai:FindBestMoveToUseStrike(token, knifeAbility)
        if loc ~= nil then
            return {score = 1.2, loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, layAbility, knifeAbility)
        MoveCinematically(ai, token, scoringInfo.loc)
        ShadowElfCinematicSpeech(ai, token, self.id)

        local mode = 1
        if layAbility:CanAfford(token, {mode = 2}) then
            local normalArea = BuildCubeArea(token, layAbility, token.loc, 1)
            local largeArea = BuildCubeArea(token, layAbility, token.loc, 2)
            local function CountShadowAllies(area)
                local count = 0
                for _,tok in pairs(dmhub.tokenInfo.TokensInShape(area)) do
                    local monsterType = tok.properties ~= nil and tok.properties:try_get("monster_type", "") or ""
                    if tok.valid and tok:IsFriend(token) and string.starts_with(monsterType, "Shadow Elf ") then
                        count = count + 1
                    end
                end
                return count
            end
            if CountShadowAllies(largeArea) >= CountShadowAllies(normalArea) + 2 then
                mode = 2
            end
            normalArea:Destroy()
            largeArea:Destroy()
        end

        local area = BuildCubeArea(token, layAbility, token.loc, mode)
        ExecuteAreaAbility(ai, token, layAbility, area, {}, {
            mode = mode,
            symbols = {mode = mode},
        })
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Elf Shade: Duskfall",
    category = "Maneuvers",
    monsters = {"Shadow Elf Shade"},
    abilities = {"Duskfall"},
    description = "After attacking, use the encounter maneuver Duskfall to end in darkness and protect the shade's mentor from that darkness's concealment.",
    score = function(self, ai, token, ability)
        if LocationProfile(token, token.loc).darkness then
            return nil
        end
        return {score = 0.8, loc = token.loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ShadowElfCinematicSpeech(ai, token, self.id)
        local area = BuildCubeArea(token, ability, token.loc, 1)
        local targets = {}
        for _,tok in pairs(dmhub.tokenInfo.TokensInShape(area)) do
            if tok.valid and tok.properties ~= nil then
                targets[#targets+1] = {token = tok}
            end
        end
        ExecuteAreaAbility(ai, token, ability, area, targets, {symbols = {mode = 1}})
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Elf Mournblade: Shadow Step",
    category = "Maneuvers",
    monsters = {"Shadow Elf Mournblade"},
    abilities = {"Shadow Step"},
    description = "When concealed, teleport through darkness to reach an otherwise unreachable attack or to finish the turn in a defensible dark space.",
    score = function(self, ai, token, ability)
        if not token.properties:IsConcealed() then
            return nil
        end

        local knife = FindAbility(token, "Knife in the Dark")
        local attacking = knife ~= nil and knife:CanAfford(token)
        local loc = FindDarkTeleportLoc(token, ability, attacking)
        if loc ~= nil and loc.str ~= token.loc.str then
            return {score = cond(attacking, 0.8, 0.3), loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, {{loc = scoringInfo.loc}}, {sleep = shadowElfCinematicPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Shadow Elf Eclipse: Grasping Shadow",
    category = "Maneuvers",
    monsters = {"Shadow Elf Eclipse"},
    abilities = {"Grasping Shadow"},
    description = "After attacking, pull and slow up to three enemies with Grasping Shadow.",
    score = GenerateStandardStrikeScoreFunction(0.8),
    execute = GenerateStandardStrikeExecuteFunction(),
}

--------------------------------------------------------------------------------
-- Eclipse villain actions.
--------------------------------------------------------------------------------

local function EclipseAlliesWithin(token, range)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if other.valid and other.properties ~= nil and other.charid ~= token.charid
            and not other.properties:IsDead() and other:IsFriend(token)
            and InitiativeQueue.GetInitiativeId(other) ~= nil
            and other:Distance(token) <= range then
            result[#result+1] = other
        end
    end
    return result
end

local function ConfigureFreeStrikeAI(ai, token)
    ai.token = token
    ai.abilities = token.properties:GetActivatedAbilities()
    ai.paths = token:CalculatePathfindingArea(token.properties:CurrentMovementSpeed()*10, {"shift"})
    ai.activeTactics = {}
    for id,tactic in pairs(ai.tactics) do
        if ai.MoveMatchesMonster(token, tactic) then
            ai.activeTactics[id] = tactic
        end
    end
end

local function FreeStrikeScoringClone(ability)
    -- ability comes from ai.abilities (GetActivatedAbilities), which returns
    -- temporary clones -- MakeTemporaryClone() would return the same object
    -- and the name/keyword mutations below would corrupt the shared instance.
    local result = DeepCopy(ability)
    result.name = "Villain Action Free Strike"
    if result.keywords ~= nil then
        result.keywords.Charge = nil
    end
    return result
end

local function FindShiftAndFreeStrikePlan(ai, token)
    ConfigureFreeStrikeAI(ai, token)
    local best = nil
    for _,ability in ipairs(ai.abilities) do
        if (ability.name == "Melee Free Strike" or ability.name == "Ranged Free Strike")
            and ability:CanAfford(token) then
            local scoringAbility = FreeStrikeScoringClone(ability)
            local loc, score = ai:FindBestMoveToUseStrike(token, scoringAbility)
            if loc ~= nil and (best == nil or score > best.score) then
                best = {
                    ability = ability,
                    loc = loc,
                    score = score,
                }
            end
        end
    end
    return best
end

local function ExecuteShiftAndFreeStrike(ai, token, eclipse)
    local plan = FindShiftAndFreeStrikePlan(ai, token)
    if plan == nil then
        return
    end

    if plan.loc.str ~= token.loc.str then
        ai:Speech(eclipse, fromTheShadowsMoveSpeech)
        ai.Sleep(shadowElfSpeechPause)

        local ok, err = ai:RunWithTokenControl(token, function()
            --GetStandardAbility returns the shared compendium entry, which is
            --never flagged as a temporary clone, so MakeTemporaryClone here is
            --a real copy and safe to mutate.
            local shift = MCDMUtils.GetStandardAbility("Shift"):MakeTemporaryClone()
            shift.range = token.properties:CurrentMovementSpeed()
            shift.targetFilter = ""
            ai:ExecuteAbility(token, shift, {{loc = plan.loc}}, {sleep = fromTheShadowsPause})
        end)

        if not ok then
            print(string.format("AI:: From the Shadows ally movement failed: %s", tostring(err)))
            return
        end
    end

    ConfigureFreeStrikeAI(ai, token)
    local scoringAbility = FreeStrikeScoringClone(plan.ability)
    local targets = ai:FindValidTargetsOfStrike(token, scoringAbility, token.loc)
    if #targets > 0 then
        table.resize_array(targets, plan.ability:GetNumTargets(token))
        for _,target in ipairs(targets) do
            target.charge = nil
        end

        ai:Speech(eclipse, FromTheShadowsStrikeSpeech(targets[1].token))
        ai.Sleep(shadowElfSpeechPause)

        local ok, err = ai:RunWithTokenControl(token, function()
            ai:ExecuteAbility(token, plan.ability, targets, {sleep = fromTheShadowsPause})
        end)

        if not ok then
            print(string.format("AI:: From the Shadows ally strike failed: %s", tostring(err)))
        end
    end
end

local function ExecuteFromTheShadows(ai, token, ability)
    -- The authored summon asks a player to place the Brush Stalker and then
    -- drives each ally through nested prompts. The AI keeps the normal summon
    -- behavior but auto-places it, then performs the shift/free-strike sequence
    -- directly so every ally chooses a tactically useful legal destination.
    -- Villain-action abilities returned by GetActivatedAbilities are already
    -- temporary clones, so MakeTemporaryClone() would return the same object.
    -- Use a deep copy before replacing the behavior list.
    local summonAbility = DeepCopy(ability)
    summonAbility.behaviors = {}
    for _,behavior in ipairs(ability.behaviors) do
        if behavior.typeName == "ActivatedAbilitySummonBehavior" then
            local summonBehavior = DeepCopy(behavior)
            summonBehavior.choosePlacement = false
            -- Auto-placement reads the applied target's loc. The authored
            -- behavior applies to the caster, which supplies a token but no
            -- loc because manual placement normally chooses the destination.
            summonBehavior.applyto = "targets"
            summonAbility.behaviors[#summonAbility.behaviors+1] = summonBehavior
        end
    end

    if #summonAbility.behaviors == 0 then
        print("AI:: From the Shadows has no summon behavior")
        return
    end

    ai:Speech(token, fromTheShadowsSpeech)
    ai.Sleep(shadowElfSpeechPause)
    ai:ExecuteAbility(token, summonAbility, {{loc = token.loc}}, {sleep = fromTheShadowsPause})
    for _,ally in ipairs(EclipseAlliesWithin(token, ability:GetRange(token.properties))) do
        ExecuteShiftAndFreeStrike(ai, ally, token)
    end
end

local function FindBestUmbralHungerCube(token, ability)
    local range = ability:GetRange(token.properties)
    local origins = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = token,
        range = range,
        radius = range,
        checklos = true,
    }
    local best = nil

    for _,loc in ipairs(origins.locations) do
        local area = BuildCubeArea(token, ability, loc, 1)
        local targets = TokensInArea(token, ability, area, {mode = 1})
        if #targets > 0 and (best == nil or #targets > best.numTargets) then
            best = {
                loc = loc,
                numTargets = #targets,
            }
        end
        area:Destroy()
    end

    origins:Destroy()
    return best
end

MonsterAI:RegisterVillainAction{
    id = "Shadow Elf Eclipse: From the Shadows",
    monsters = {"Shadow Elf Eclipse"},
    abilities = {"From the Shadows"},
    description = "Summon a Brush Stalker, then shift nearby allies into useful free strikes.",
    score = function(self, ai, token, ability)
        local usefulAllies = 0
        for _,ally in ipairs(EclipseAlliesWithin(token, ability:GetRange(token.properties))) do
            if FindShiftAndFreeStrikePlan(ai, ally) ~= nil then
                usefulAllies = usefulAllies + 1
            end
        end
        return {
            score = math.min(1, 0.6 + usefulAllies*0.08),
            usefulAllies = usefulAllies,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteFromTheShadows(ai, token, ability)
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Shadow Elf Eclipse: Cast Away All Hope",
    monsters = {"Shadow Elf Eclipse"},
    abilities = {"Cast Away All Hope"},
    description = "Strip surges from nearby enemies and protect all allies from those enemies until the end of the round.",
    score = function(self, ai, token, ability)
        local targets = 0
        local surges = 0
        local range = ability:GetRange(token.properties)
        for _,enemy in ipairs(ai.enemyTokens) do
            if enemy:Distance(token) <= range and ability:TargetPassesFilter(token, enemy, {}) then
                targets = targets + 1
                surges = surges + enemy.properties:GetAvailableSurges()
            end
        end
        if targets == 0 then
            return nil
        end
        return {
            score = math.min(1, 0.4 + targets*0.1 + surges*0.06),
            targets = targets,
            surges = surges,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ShadowElfCinematicSpeech(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = shadowElfCinematicPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Shadow Elf Eclipse: Umbral Hunger",
    monsters = {"Shadow Elf Eclipse"},
    abilities = {"Umbral Hunger"},
    description = "Place the persistent darkness cube where it catches the most enemies.",
    score = function(self, ai, token, ability)
        local cube = FindBestUmbralHungerCube(token, ability)
        if cube == nil then
            return nil
        end
        return {
            score = math.min(1, 0.4 + cube.numTargets*0.2),
            cube = cube,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ShadowElfCinematicSpeech(ai, token, self.id)
        local area = BuildCubeArea(token, ability, scoringInfo.cube.loc, 1)
        local targets = TokensInArea(token, ability, area, {mode = 1})
        ExecuteAreaAbility(ai, token, ability, area, targets, {symbols = {mode = 1}})
    end,
}

--------------------------------------------------------------------------------
-- Secondary prompts.
--------------------------------------------------------------------------------

MonsterAI:RegisterPrompt{
    prompts = {"Shadow Elf Assassin:Allies Free Strike Against Target"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return {targets = FindPromptTargets(casterToken, abilityClone, symbols)}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Shadow Elf Noctis Mage:Blotting Bolt Double Bane"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return {targets = FindPromptTargets(casterToken, abilityClone, symbols)}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Shadow Elf Panther:Dusk Cleave Free Strike"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return {
            targets = FindPromptTargets(casterToken, abilityClone, symbols, function(tok)
                return not tok:IsFriend(casterToken)
            end),
        }
    end,
}

--------------------------------------------------------------------------------
-- Triggered actions.
--------------------------------------------------------------------------------

MonsterAI:RegisterTrigger{
    id = "Shadow Elf Knightfell: Trick of the Eye",
    monsters = {"Shadow Elf Knightfell"},
    triggers = {"Trick of the Eye"},
    description = "Use Trick of the Eye to split strike damage dealt to a nearby ally.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Shadow Elf Moondancer: Dissolve",
    monsters = {"Shadow Elf Moondancer"},
    abilityGuids = {"e96013c1-cc90-439d-9503-a7cbf16be31c"},
    abilities = {"Dissolve"},
    description = "After taking strike damage, teleport to the safest available space in darkness.",
    handler = function(ai, token, triggerInfo)
        local ability = FindAbility(token, "Dissolve")
        local loc = ability ~= nil and FindDarkTeleportLoc(token, ability, false) or nil
        if loc == nil then
            return {dismiss = true}
        end
        return {
            activate = true,
            expectedPrompt = {
                casterid = token.charid,
                targets = {{loc = loc}},
                sleep = 0.3,
            },
        }
    end,
}

MonsterAI:RegisterTrigger{
    id = "Shadow Elf Eclipse: Put It Out!",
    monsters = {"Shadow Elf Eclipse"},
    triggers = {"Put It Out!"},
    description = "Use Put It Out! to impose a double bane on an enemy ability that emits light.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}
