local mod = dmhub.GetModLoading()

--Monster AI for the Angulotls band: Clawfish, Angulotl Cleaver, Pollywog, Dart,
--Needler, Slink, Wave and Daybringer, plus the band's start-of-turn Malice
--features. Minion signature strikes are coordinated by the shared squad logic;
--this file answers the jumps and shifts those strikes ask for, and adds the
--non-minion moves, triggers and villain actions. Waves lay Noxious Bubbles that
--the others pop on the heroes; Tonguelash pulls into bubbles and hazard zones
--(Toxic Plants).

local movementPause = 0.6
local stationaryPause = 0.35
local abilityPause = 0.9

local angulotlGroup = {"Angulotls"}

local angulotlMonsters = {
    "Clawfish",
    "Angulotl Cleaver",
    "Angulotl Pollywog",
    "Angulotl Dart",
    "Angulotl Needler",
    "Angulotl Slink",
    "Angulotl Wave",
    "Angulotl Daybringer",
}

local angulotlNonMinions = {
    "Angulotl Needler",
    "Angulotl Slink",
    "Angulotl Wave",
    "Angulotl Daybringer",
}

local angulotlMonsterSet = {}
for _,monsterType in ipairs(angulotlMonsters) do
    angulotlMonsterSet[monsterType] = true
end

local wetEffectId = "b936df43-5c0e-4046-9221-ce360fa5131b"
local sunLampEffectId = "814f6bd8-0f0c-4712-acd9-7f1fdc636c1f"
local illuminatedEffectId = "f905e96c-6b89-4d88-9688-71fabc39c9c2"

--Spoken lines, kept together so they are easy to revise after playtesting.
local speech = {
    newDawn = {"Rise, little ones!", "The clutch hatches!", "Swarm them, my tadpoles!"},
    plagueOfFrogs = {"Leap, my kin!", "Fall upon them like rain!", "Hop to it!"},
    itIsDay = {"It is day!", "Behold the dawn!", "The sun rises on you!"},
    rainfall = {"Let the skies weep!", "Rain, come to us!"},
    resonatingCroak = {"CROOOAK!", "Sing, my kin!"},
    leapfrog = {"Over and onward!", "Leapfrog!"},
    sunLamp = {"Bask in my light!", "Warmth for the clutch!"},
    quickSnack = {"Mm, crunchy.", "Sorry, little one."},
    noxiousBubble = {"A gift from the marsh!", "Breathe deep!", "Bubble, bubble!"},
    popBubble = {"Pop!", "Breathe it in!"},
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

--Matches by stat block and by keyword, so angulotls from other content count too.
local function IsAngulotl(token)
    if not LiveCreature(token) then
        return false
    end
    if angulotlMonsterSet[MonsterType(token)] then
        return true
    end
    local keywords = token.properties:try_get("keywords")
    return type(keywords) == "table" and keywords.Angulotl == true
end

local function IsMinion(token)
    return token.properties:try_get("minion", false) == true
end

local function FindTokenByCharid(charid)
    if type(charid) ~= "string" or charid == "" then
        return nil
    end
    return dmhub.GetTokenById(charid)
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

local function IsWet(token)
    return HasOngoingEffect(token, wetEffectId)
end

--Wet grants angulotls this attribute. Read the attribute rather than the
--effect so the AI follows whatever the rules actually applied.
local function DoesNotProvoke(token)
    return (token.properties:CalculateNamedCustomAttribute("Immunity from Opportunity Attack") or 0) > 0
end

--Clamped: temporary Stamina can push current Stamina above the maximum.
--MaxHitpoints(), not the max_hitpoints field: on a hero that field is a stale 10.
local function StaminaFraction(token)
    local fraction = token.properties:CurrentHitpoints() / math.max(1, token.properties:MaxHitpoints())
    return math.max(0, math.min(1, fraction))
end

local function MissingStamina(token)
    return math.max(0, token.properties:MaxHitpoints() - token.properties:CurrentHitpoints())
end

local function RemainingMovement(token)
    return math.max(0, token.properties:CurrentMovementSpeed()
        - token.properties:DistanceMovedThisTurn())
end

local function LocKey(loc)
    return loc.xyfloorOnly.str
end

local function FindAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name then
            return ability
        end
    end
end

--The token's main strike, used to judge how close it wants to stand to enemies.
local function SignatureStrikeRange(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.categorization == "Signature Ability" and ability:HasKeyword("Strike") then
            return ability:GetRange(token.properties)
        end
    end
    return 1
end

local function MoveCinematically(ai, token, loc)
    local moving = loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc)
    if moving then
        ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
    end
    ai.Sleep(moving and movementPause or stationaryPause)
end

local function LiveEnemies(ai)
    local result = {}
    for _,enemy in ipairs(ai.enemyTokens or {}) do
        if LiveCreature(enemy) then
            result[#result+1] = enemy
        end
    end
    return result
end

--Live friendly creatures, read from the map so it also works out of turn.
local function FriendlyAngulotls(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if IsAngulotl(other) and other:IsFriend(token) then
            result[#result+1] = other
        end
    end
    return result
end

local function HostileCreatures(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and not other:IsFriend(token) then
            result[#result+1] = other
        end
    end
    return result
end

local function AdjacentAngulotlsAt(token, loc)
    local result = 0
    for _,other in ipairs(dmhub.allTokens) do
        if other.charid ~= token.charid and IsAngulotl(other) and other:IsFriend(token)
            and other:Distance(loc) <= 1 then
            result = result + 1
        end
    end
    return result
end

local function TokensInArea(casterToken, ability, area, symbols)
    local result = {}
    symbols = symbols or {}
    symbols.targetArea = area
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if target.valid and ability:TargetPassesFilter(casterToken, target, symbols) then
            result[#result+1] = {token = target}
        end
    end
    return result
end

--Every live creature on the map that passes the ability's own target filter.
local function MapTargets(casterToken, ability)
    local area = dmhub.CalculateShape{
        shape = "map",
        token = casterToken,
    }
    local targets = {}
    for _,targetInfo in ipairs(TokensInArea(casterToken, ability, area, {})) do
        if LiveCreature(targetInfo.token) then
            targets[#targets+1] = targetInfo
        end
    end
    return area, targets
end

local function ExecuteMapAbility(ai, token, ability)
    local area, targets = MapTargets(token, ability)
    ai:ExecuteAbility(token, DeepCopy(ability), targets, {
        sleep = abilityPause,
        symbols = {targetArea = area},
        targetArea = area,
        telegraphArea = false,
    })
end

local function StrikeTargetScore(target, edges)
    if target.isObject then
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
    end
end

local function StrikeExecute(scorefn)
    return function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, scorefn)
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end
end

--------------------------------------------------------------------------------
-- Choosing where to land after a jump, shift, or summon.
--------------------------------------------------------------------------------

local function LocIsConcealed(loc)
    local concealed = false
    pcall(function()
        local lookup = GenerateSymbols(Loc.Create(loc)) --[[@as fun(symbol: string): any]]
        concealed = lookup("concealment") == true
    end)
    return concealed
end

--True when no enemy has a clear view of the square, so Hide can succeed there.
local function CanHideAt(ai, token, loc, enemies)
    if LocIsConcealed(loc) then
        return true
    end
    local seen = false
    local covered = false
    ai:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        for _,enemy in ipairs(enemies) do
            local los = enemy:GetLineOfSight(token, enemy.properties:GetPierceWalls())
            if los >= 1 then
                seen = true
                break
            elseif los > 0 then
                covered = true
            end
        end
    end)
    return covered and not seen
end

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

--Free squares a token can land on within range of a starting square.
local function LandingCandidates(token, range, reserved, originToken)
    local result = {}
    if range == nil or range < 1 then
        return result
    end
    local shape = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = originToken or token,
        radius = range,
        checklos = true,
    }
    for _,loc in ipairs(shape.locations or {}) do
        if LocKey(loc) ~= LocKey(token.loc) and LandingIsFree(token, loc, reserved) then
            result[#result+1] = loc
        end
    end
    return result
end

local function EnemyContact(enemies, loc)
    local nearest = 999
    local adjacent = 0
    for _,enemy in ipairs(enemies) do
        local distance = enemy:Distance(loc)
        nearest = math.min(nearest, distance)
        if distance <= 1 then
            adjacent = adjacent + 1
        end
    end
    return nearest, adjacent
end

--A square to fight from: melee angulotls want an enemy next to them, ranged
--ones want a target inside their reach without being adjacent. All of them
--prefer staying close to the clutch.
local function EngageScore(token, loc, enemies, reach)
    local nearest, adjacent = EnemyContact(enemies, loc)
    local score
    if reach <= 1 then
        score = -nearest + cond(nearest <= 1, 3, 0) - math.max(0, adjacent - 2)*0.5
    elseif nearest <= 1 then
        score = -2 - adjacent*0.5
    elseif nearest <= reach then
        score = 3 - nearest*0.05
    else
        score = -(nearest - reach)
    end
    return score + math.min(2, AdjacentAngulotlsAt(token, loc))*0.3
end

--Hit-and-run: out of reach of a counterattack, but close enough to strike
--again next turn, ideally hidden or beside an ally.
local function SkirmishScore(token, loc, enemies)
    local nearest, adjacent = EnemyContact(enemies, loc)
    local score = -adjacent*2.5
    if nearest >= 2 and nearest <= 4 then
        score = score + 2
    elseif nearest > 4 then
        score = score + 2 - (nearest - 4)*0.5
    end
    score = score + cond(LocIsConcealed(loc), 1, 0)
    return score + math.min(2, AdjacentAngulotlsAt(token, loc))*0.3
end

--A jump that leaves an adjacent enemy's reach provokes an opportunity attack,
--which kills a minion outright. Wet angulotls are immune to them.
local function ProvokePenalty(token, loc, adjacentNow)
    if #adjacentNow == 0 or DoesNotProvoke(token) then
        return 0
    end
    local left = 0
    for _,enemy in ipairs(adjacentNow) do
        if enemy:Distance(loc) > 1 then
            left = left + 1
        end
    end
    return left*cond(IsMinion(token), 10, 3)
end

local function EnemiesAdjacentTo(token, enemies)
    local result = {}
    for _,enemy in ipairs(enemies) do
        if MonsterAI.TargetDistance(token, enemy) <= 1 then
            result[#result+1] = enemy
        end
    end
    return result
end

--A creature holding a zone (the Monster AI "Hold" directive, e.g. the
--Daybringer at the Ritual Basin) never jumps off it, and one off it jumps back.
local function HoldLandingScore(token, loc)
    if MonsterAI.Holds(token) and MonsterAI.InHoldZone(token, loc) then
        return 5
    end
    return 0
end

--Best landing for a purpose ("engage" or "skirmish"). Returns loc and score.
local function FindBestLanding(token, range, purpose, enemies, reserved)
    local reach = SignatureStrikeRange(token)
    local adjacentNow = EnemiesAdjacentTo(token, enemies)
    local best = nil
    local bestScore = nil
    for _,loc in ipairs(LandingCandidates(token, range, reserved)) do
        if MonsterAI.HoldPermits(token, loc) then
            local score
            if purpose == "skirmish" then
                score = SkirmishScore(token, loc, enemies)
            else
                score = EngageScore(token, loc, enemies, reach)
            end
            score = score - ProvokePenalty(token, loc, adjacentNow)
                - token.loc:DistanceInTiles(loc)*0.01 + HoldLandingScore(token, loc)
            if bestScore == nil or score > bestScore then
                best = loc
                bestScore = score
            end
        end
    end
    return best, bestScore
end

local function CurrentLandingScore(token, purpose, enemies)
    local score
    if purpose == "skirmish" then
        score = SkirmishScore(token, token.loc, enemies)
    else
        score = EngageScore(token, token.loc, enemies, SignatureStrikeRange(token))
    end
    return score + HoldLandingScore(token, token.loc)
end

--Planned jump destinations for prompts that arrive one creature at a time
--(Plague of Frogs), keyed by the jumping creature's charid.
local function TakeJumpPlan(ai, charid)
    local plans = ai:try_get("_tmp_angulotlJumpPlans")
    if plans == nil then
        return nil
    end
    local loc = plans[charid]
    plans[charid] = nil
    return loc
end

local function ShowJump(token, loc)
    token:MarkMovementArrow(loc, {straightline = true, ignorecreatures = true})
    MonsterAI.Sleep(movementPause)
    token:ClearMovementArrow()
end

--Answers a jump prompt: a planned square when there is one, otherwise the
--best square for the given purpose. An empty answer skips the jump.
local function AnswerJumpPrompt(ai, casterToken, abilityClone, purpose)
    local range = abilityClone:GetRange(casterToken.properties)
    local planned = TakeJumpPlan(ai, casterToken.charid)
    if planned ~= nil and casterToken.loc:DistanceInTiles(planned) <= range
        and LandingIsFree(casterToken, planned) then
        ShowJump(casterToken, planned)
        return {targets = {{loc = planned}}}
    end

    local enemies = HostileCreatures(casterToken)
    local loc, score = FindBestLanding(casterToken, range, purpose, enemies)
    if loc ~= nil and score ~= nil and score > CurrentLandingScore(casterToken, purpose, enemies) then
        ShowJump(casterToken, loc)
        return {targets = {{loc = loc}}}
    end
    return {targets = {}}
end

--------------------------------------------------------------------------------
-- Hazards: Noxious Bubbles and hazard zones such as Toxic Plants.
--------------------------------------------------------------------------------

local noxiousBubbleAuraName = "Noxious Bubble"

--True when a wave's Noxious Bubble covers the square.
local function BubbleAt(loc)
    for _,aura in ipairs(game.GetAurasAtLoc(loc.xyfloorOnly) or {}) do
        local instance = aura.auraInstance
        local auraDef = instance ~= nil and instance:try_get("aura") or nil
        if auraDef ~= nil and auraDef:try_get("name") == noxiousBubbleAuraName then
            return true
        end
    end
    return false
end

--A zone hurts whoever enters it when its Environmental Keyword makes an entry
--power roll (Toxic Plants, Lava, Quicksand) or deals movement damage.
local function KeywordIsHazard(keyword)
    if keyword == nil then
        return false
    end
    if keyword:try_get("powerRollEnabled", false) then
        return true
    end
    return keyword:try_get("movedamage", "none") ~= "none"
        and (tonumber(keyword:try_get("damage", 0)) or 0) > 0
end

local function HazardZoneAt(loc)
    local environmentalKeywordType = rawget(_G, "EnvironmentalKeyword")
    if environmentalKeywordType == nil or environmentalKeywordType.AuraInstancesCoveringSquare == nil then
        return false
    end
    local keywords = dmhub.GetTable("environmentalKeywords") or {}
    for _,instance in ipairs(environmentalKeywordType.AuraInstancesCoveringSquare(loc)) do
        local auraDef = instance:try_get("aura")
        local keywordid = auraDef ~= nil and auraDef:try_get("environmentalKeywordId") or nil
        if keywordid ~= nil and KeywordIsHazard(keywords[keywordid]) then
            return true
        end
    end
    return false
end

--Per-frame caches: tactics are scored for every square and every target, and
--the answers cannot change until the AI yields.
local g_frameCache = {time = -1, hazards = {}, wetEnemies = {}}

local function FrameCache()
    local now = dmhub.Time()
    if g_frameCache.time ~= now then
        g_frameCache = {time = now, hazards = {}, wetEnemies = {}}
    end
    return g_frameCache
end

--1 when a square hurts whoever lands on it: a hazard zone, or a Noxious
--Bubble (entering pops it). Used both to keep angulotls out and to pull
--heroes in.
local function HazardAt(loc)
    local cache = FrameCache().hazards
    local key = LocKey(loc)
    local value = cache[key]
    if value == nil then
        value = cond(HazardZoneAt(loc) or BubbleAt(loc), 1, 0)
        cache[key] = value
    end
    return value
end

--The wet creatures hostile to the token.
local function WetEnemiesOf(token)
    local cache = FrameCache().wetEnemies
    local result = cache[token.charid]
    if result == nil then
        result = {}
        for _,other in ipairs(HostileCreatures(token)) do
            if IsWet(other) then
                result[#result+1] = other
            end
        end
        cache[token.charid] = result
    end
    return result
end

--------------------------------------------------------------------------------
-- Passive formation preference.
--------------------------------------------------------------------------------

MonsterAI:RegisterTactic{
    id = "Angulotl: Clutch Formation",
    monsters = angulotlMonsters,
    description = "Prefer strike positions next to another angulotl; the band fights in close, coherent groups.",
    score = function(self, token, tokenLoc, enemy, ability)
        if AdjacentAngulotlsAt(token, tokenLoc) > 0 then
            return 0.3
        end
    end,
}

--Toxic Plants daze angulotls too, and stopping in a bubble pops it for nothing.
MonsterAI:RegisterTactic{
    id = "Angulotl: Avoid Hazards",
    monsters = angulotlMonsters,
    description = "Do not strike from a hazard zone (Toxic Plants) or from inside a Noxious Bubble.",
    score = function(self, token, tokenLoc, enemy, ability)
        if HazardAt(tokenLoc) > 0 then
            return -2
        end
    end,
}

--Shocking hits each wet enemy within 2 at the start of the clawfish's turn, so
--end the turn near wet enemies and hook the wet ones first.
MonsterAI:RegisterTactic{
    id = "Clawfish: Shocking",
    monsters = {"Clawfish"},
    description = "Prefer wet targets, and squares within 2 of wet enemies so Shocking hits them next turn.",
    score = function(self, token, tokenLoc, enemy, ability)
        local bonus = 0
        local near = 0
        for _,wet in ipairs(WetEnemiesOf(token)) do
            if wet.charid == enemy.charid then
                bonus = bonus + 0.3
            end
            if wet:Distance(tokenLoc) <= 2 then
                near = near + 1
            end
        end
        bonus = bonus + math.min(3, near)*0.25
        if bonus > 0 then
            return bonus
        end
    end,
}

--------------------------------------------------------------------------------
-- Minion follow-ups: Hop and Chop's jump, Nip's shift.
--------------------------------------------------------------------------------

MonsterAI:RegisterPrompt{
    prompts = {"Angulotl Cleaver:Hop (Jump up to 4)"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return AnswerJumpPrompt(ai, casterToken, abilityClone, "skirmish")
    end,
}

--After Nip, a pollywog edges toward a wounded angulotl who can eat it, or
--otherwise to a square that keeps it in the fight without being swarmed.
local function PollywogShiftScore(token, loc, enemies)
    local nearest, adjacent = EnemyContact(enemies, loc)
    local score = cond(nearest <= 1, 1, -nearest*0.3) - math.max(0, adjacent - 1)*0.8
    for _,ally in ipairs(FriendlyAngulotls(token)) do
        if ally.charid ~= token.charid and not IsMinion(ally)
            and MissingStamina(ally) >= 4 and ally:Distance(loc) <= 1 then
            score = score + 1.5
            break
        end
    end
    return score + math.random()*0.05
end

MonsterAI:RegisterPrompt{
    prompts = {"Angulotl Pollywog:Shift"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties)
        local enemies = HostileCreatures(casterToken)
        local best = nil
        local bestScore = PollywogShiftScore(casterToken, casterToken.loc, enemies)
        for _,info in pairs(casterToken:CalculatePathfindingArea(range*10, {"shift"})) do
            if LandingIsFree(casterToken, info.loc) then
                local score = PollywogShiftScore(casterToken, info.loc, enemies)
                if score > bestScore then
                    best = info.loc
                    bestScore = score
                end
            end
        end
        if best == nil then
            return {targets = {}}
        end
        casterToken:MarkMovementArrow(best, {straightline = true, ignorecreatures = false})
        MonsterAI.Sleep(movementPause)
        casterToken:ClearMovementArrow()
        return {targets = {{loc = best}}}
    end,
}

--------------------------------------------------------------------------------
-- Needler, Wave and Slink strikes.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Angulotl Needler: Blowgun",
    category = "Main Actions",
    monsters = {"Angulotl Needler"},
    abilities = {"Blowgun"},
    description = "Snipe from long range, spreading damage toward healthier enemies.",
    score = StrikeScore(1.05, StrikeTargetScore),
    execute = StrikeExecute(StrikeTargetScore),
}

--Illuminated creatures give every strike against them an edge, so spread the
--beams to creatures that are not lit up yet.
local function RefulgentBeamsTargetScore(target, edges)
    if target.isObject then
        return 0.1 + (edges or 0)*0.1
    end
    return StrikeTargetScore(target, edges) + cond(HasOngoingEffect(target, illuminatedEffectId), 0, 0.2)
end

MonsterAI:RegisterMove{
    id = "Angulotl Wave: Refulgent Beams",
    category = "Main Actions",
    monsters = {"Angulotl Wave"},
    abilities = {"Refulgent Beams"},
    description = "Strike two enemies with holy light, preferring ones that are not already illuminated.",
    score = StrikeScore(1.05, RefulgentBeamsTargetScore),
    execute = StrikeExecute(RefulgentBeamsTargetScore),
}

MonsterAI:RegisterMove{
    id = "Angulotl Slink: Tonguelash",
    category = "Main Actions",
    monsters = {"Angulotl Slink"},
    abilities = {"Tonguelash"},
    description = "Lash an enemy from up to 6 squares away and pull them in.",
    score = StrikeScore(1.1, StrikeTargetScore),
    execute = StrikeExecute(StrikeTargetScore),
}

--Slinks drag heroes into the toxic plants (and a Noxious Bubble pops on
--whoever is pulled into it), so a legal pull that lands an enemy on a hazard
--beats the shared handler's choice, which only maximises distance. Returns
--the furthest such landing, or nil. casterToken is the creature being pulled.
local function FindHazardPullLanding(invokerToken, casterToken, abilityClone, symbols, range)
    local movementSymbols = {}
    for key,value in pairs(symbols or {}) do
        movementSymbols[key] = value
    end
    movementSymbols.range = movementSymbols.range or range
    movementSymbols.invoker = movementSymbols.invoker or invokerToken.properties
    ---@type fun(loc: Loc): boolean
    local legal = abilityClone:TargetLocPassesFilterPredicate(casterToken, movementSymbols)
        or function() return true end

    local shape = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = casterToken,
        radius = range,
        checklos = false,
    }
    local best = nil
    local bestDistance = nil
    for _,loc in ipairs(shape.locations or {}) do
        if HazardAt(loc) > 0 and legal(loc) then
            --aim on the ground: a target altitude means "this high above it".
            loc = loc:WithAltitude(0)
            local preview = casterToken:MarkMovementArrow(loc, {
                straightline = true,
                ignorecreatures = false,
                forcedMovementDistance = range,
            })
            local path = preview ~= nil and preview.path or nil
            if path ~= nil and LocKey(path.destination) == LocKey(loc) then
                local distance = path.destination:DistanceInTiles(path.origin)
                if distance > 0 and (bestDistance == nil or distance > bestDistance) then
                    best = loc
                    bestDistance = distance
                end
            end
        end
    end
    casterToken:ClearMovementArrow()
    return best
end

--Tonguelash's pull: into a hazard when one is in reach, otherwise the shared
--pull handler. When the target is boxed in and cannot move, skip the pull
--rather than stall the turn on a Director prompt.
MonsterAI:RegisterPrompt{
    prompts = {"Angulotl Slink:Pull!"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if invokerToken ~= nil and not casterToken:IsFriend(invokerToken) then
            local range = abilityClone:GetRange(casterToken.properties)
            local landing = FindHazardPullLanding(invokerToken, casterToken, abilityClone, symbols, range)
            if landing ~= nil then
                casterToken:MarkMovementArrow(landing, {
                    straightline = true,
                    ignorecreatures = false,
                    forcedMovementDistance = range,
                })
                MonsterAI.Sleep(movementPause)
                casterToken:ClearMovementArrow()
                return {targets = {{loc = landing}}}
            end
        end

        local generic = MonsterAI.prompts["Pull!"]
        local result = nil
        if generic ~= nil then
            result = generic.handler(ai, invokerToken, casterToken, abilityClone, symbols, options)
        end
        return result or {targets = {}}
    end,
}

local function FindHopToItPlan(ai, token)
    local range = math.min(3, RemainingMovement(token))
    if range < 1 then
        return nil, "no movement remains for the jump"
    end
    local enemies = LiveEnemies(ai)
    if #enemies == 0 then
        return nil, "no enemies"
    end
    local reach = SignatureStrikeRange(token)
    local adjacentNow = EnemiesAdjacentTo(token, enemies)
    local best = nil
    for _,loc in ipairs(LandingCandidates(token, range)) do
        local nearest, adjacent = EnemyContact(enemies, loc)
        if adjacent == 0 and nearest <= reach and ProvokePenalty(token, loc, adjacentNow) == 0
            and CanHideAt(ai, token, loc, enemies) then
            local score = SkirmishScore(token, loc, enemies) - token.loc:DistanceInTiles(loc)*0.01
            if best == nil or score > best.value then
                best = {loc = loc, value = score}
            end
        end
    end
    if best == nil then
        return nil, "no square within the jump allows hiding while staying in Tonguelash reach"
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Angulotl Slink: Hop To It",
    category = "Maneuvers",
    monsters = {"Angulotl Slink"},
    abilities = {"Hop to It"},
    description = "After lashing, spend 2 Malice to jump up to 3 squares into cover or concealment and hide.",
    score = function(self, ai, token, ability)
        if token.properties:HasNamedCondition("Hidden") then
            return nil, "already hidden"
        end
        local tonguelash = FindAbility(token, "Tonguelash")
        if tonguelash ~= nil and tonguelash:CanAfford(token) then
            return nil, "Tonguelash is still available this turn"
        end
        local plan, reason = FindHopToItPlan(ai, token)
        if plan == nil then
            return nil, reason
        end
        return {score = 0.62, loc = plan.loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:SetTargetsForExpectedPrompt{
            casterid = token.charid,
            targets = {{loc = scoringInfo.loc}},
            sleep = movementPause,
        }
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        ai._tmp_expectedPromptTarget = nil
    end,
}

--------------------------------------------------------------------------------
-- Angulotl Wave: Noxious Bubble, and popping bubbles on the heroes.
--------------------------------------------------------------------------------

--The non-minion leader the waves shield with their bubbles (the daybringer).
local function FindLeader(token)
    for _,ally in ipairs(FriendlyAngulotls(token)) do
        local role = string.lower(ally.properties:try_get("role", "") or "")
        if not IsMinion(ally) and string.find(role, "leader", 1, true) ~= nil then
            return ally
        end
    end
    return nil
end

--The 2 cube a bubble fills around a square. range is passed explicitly so a
--far square is not clamped back toward the caster while planning.
local function BuildBubbleArea(token, ability, center, range, originLoc)
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(center),
        token = token,
        range = range,
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

--Every square some bubble was cast on, read from the casters' own aura lists.
--BubbleAt asks the engine's aura index instead, which only holds bubbles that
--are live on the map (see the objectid note in the Aixco report); this list
--also sees any that are not, so two waves never stack bubbles on one spot.
local function CastBubbleSquares()
    local result = {}
    for _,token in ipairs(dmhub.allTokens) do
        if token.properties ~= nil and not token.isObject then
            for _,instance in ipairs(token.properties:try_get("auras", {})) do
                local auraDef = instance:try_get("aura")
                local area = instance:try_get("area")
                if auraDef ~= nil and area ~= nil and auraDef:try_get("name") == noxiousBubbleAuraName then
                    for _,loc in ipairs(area.locations or {}) do
                        result[LocKey(loc)] = true
                    end
                end
            end
        end
    end
    return result
end

--The bubble needs unoccupied space, and two bubbles may not overlap.
local function BubbleSquaresAreFree(locs, castBubbles)
    if #locs == 0 then
        return false
    end
    for _,loc in ipairs(locs) do
        if BubbleAt(loc) or (castBubbles ~= nil and castBubbles[LocKey(loc)]) then
            return false
        end
        for _,other in ipairs(dmhub.GetTokensAtLoc(loc) or {}) do
            if other.valid then
                return false
            end
        end
    end
    return true
end

local function MinDistanceToSquares(token, locs)
    local result = 999
    for _,loc in ipairs(locs) do
        result = math.min(result, token:Distance(loc))
    end
    return result
end

--How good a bubble on these squares is: enemies next to it are caught when it
--pops, dry angulotls next to it get wet (immune to opportunity attacks), and a
--bubble between the enemy and the leader blocks the way to him.
local function BubbleValue(locs, enemies, allies, leader)
    local caught = 0
    for _,enemy in ipairs(enemies) do
        if MinDistanceToSquares(enemy, locs) <= 1 then
            caught = caught + 1
        end
    end

    local soaked = 0
    for _,ally in ipairs(allies) do
        if not IsWet(ally) and MinDistanceToSquares(ally, locs) <= 1 then
            soaked = soaked + 1
        end
    end

    local guard = 0
    if leader ~= nil and MinDistanceToSquares(leader, locs) <= 2 then
        for _,enemy in ipairs(enemies) do
            local toLeader = enemy:Distance(leader)
            if toLeader <= 8 and MinDistanceToSquares(enemy, locs) < toLeader then
                guard = guard + 0.6
            end
        end
    end

    return caught + math.min(2, soaked)*0.25 + math.min(1.2, guard), caught
end

--A bubble needs at least this much value: two enemies caught, or one enemy
--caught while it also guards the leader.
local minimumBubbleValue = 1.8

local function FindNoxiousBubblePlan(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local enemies = LiveEnemies(ai)
    if #enemies == 0 then
        return nil, "no enemies"
    end
    local allies = FriendlyAngulotls(token)
    local leader = FindLeader(token)

    --Where the wave can cast from this turn, cheapest first. Its own square
    --comes first: the movement paths do not list it.
    local origins = {{loc = token.loc, cost = 0}}
    for _,info in pairs(ai.paths or {}) do
        if LocKey(info.loc) ~= LocKey(token.loc) then
            origins[#origins+1] = {loc = info.loc, cost = info.cost or 0}
        end
    end
    table.sort(origins, function(a, b) return a.cost < b.cost end)
    local castBubbles = CastBubbleSquares()
    local maxReach = range + RemainingMovement(token)

    --Candidate squares: around each enemy in reach, and around the leader.
    local centers = {}
    local seen = {}
    local function AddCenters(loc, radius)
        for dx=-radius,radius do
            for dy=-radius,radius do
                local center = loc:dir(dx, dy)
                if center.valid and not seen[LocKey(center)] then
                    seen[LocKey(center)] = true
                    centers[#centers+1] = center
                end
            end
        end
    end
    for _,enemy in ipairs(enemies) do
        if token:Distance(enemy) <= maxReach + 2 then
            AddCenters(enemy.loc, 2)
        end
    end
    if leader ~= nil then
        AddCenters(leader.loc, 3)
    end

    local scored = {}
    for _,center in ipairs(centers) do
        --Just far enough to reach the center unclamped. The engine's cube cost
        --grew with the square of this range: 999 took ~680 ms a call.
        local reach = token:Distance(center) + ability:GetRadius(token.properties) + 1
        local area = BuildBubbleArea(token, ability, center, reach, nil)
        local locs = area.locations or {}
        if BubbleSquaresAreFree(locs, castBubbles) then
            local value, caught = BubbleValue(locs, enemies, allies, leader)
            if value >= minimumBubbleValue and caught > 0 then
                scored[#scored+1] = {center = center, value = value, caught = caught}
            end
        end
        DestroyArea(area)
    end
    if #scored == 0 then
        return nil, "no free 2 cube catches two enemies or guards the leader"
    end
    table.sort(scored, function(a, b) return a.value > b.value end)

    --The best few: find the cheapest origin in range with line of effect that
    --does not provoke an opportunity attack on the way.
    local pierceWalls = token.properties:GetPierceWalls()
    local adjacentNow = EnemiesAdjacentTo(token, enemies)
    for i=1,math.min(6, #scored) do
        local candidate = scored[i]
        local checks = 0
        for _,origin in ipairs(origins) do
            if checks >= 12 then
                break
            end
            if origin.loc:DistanceInTiles(candidate.center) <= range
                and ProvokePenalty(token, origin.loc, adjacentNow) == 0 then
                checks = checks + 1
                local visible = false
                ai:ExecuteWithTheoreticalMovementLoc(token, origin.loc, function()
                    visible = token:GetLineOfSight(candidate.center, pierceWalls) > 0
                end)
                if visible then
                    candidate.loc = origin.loc
                    candidate.cost = origin.cost
                    return candidate
                end
            end
        end
    end
    return nil, "no reachable square has line of effect to a good bubble"
end

MonsterAI:RegisterMove{
    id = "Angulotl Wave: Noxious Bubble",
    category = "Main Actions",
    monsters = {"Angulotl Wave"},
    abilities = {"Noxious Bubble"},
    description = "Spend 2 Malice on a toxic bubble beside two or more enemies, or between the enemy and the daybringer, for the clutch to pop later.",
    score = function(self, ai, token, ability)
        local plan, reason = FindNoxiousBubblePlan(ai, token, ability)
        if plan == nil then
            return nil, reason
        end
        plan.score = 1.0 + math.min(0.4, (plan.value - minimumBubbleValue)*0.15 + 0.1)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local area = BuildBubbleArea(token, ability, scoringInfo.center,
            ability:GetRange(token.properties), nil)
        if not BubbleSquaresAreFree(area.locations or {}, CastBubbleSquares()) then
            DestroyArea(area)
            return
        end
        ai:Speech(token, speech.noxiousBubble)
        ai.Sleep(stationaryPause)
        ai:ExecuteAbility(token, ability, {}, {
            sleep = abilityPause,
            symbols = {targetArea = area},
            targetArea = area,
        })
        DestroyArea(area)
    end,
}

--The bubble bursts on whoever touches it, catching everything within 2 of
--them (the data's stand-in for "adjacent to the bubble"). A non-minion steps
--in when that catches two or more enemies, then keeps fighting wet.
local function FindBubblePopPlan(ai, token)
    local enemies = LiveEnemies(ai)
    if #enemies < 2 then
        return nil, "fewer than two enemies"
    end

    local reachable = {}
    for _,info in pairs(ai.paths or {}) do
        reachable[LocKey(info.loc)] = info
    end

    local adjacentNow = EnemiesAdjacentTo(token, enemies)
    local seen = {}
    local best = nil
    for _,enemy in ipairs(enemies) do
        for dx=-2,2 do
            for dy=-2,2 do
                local loc = enemy.loc:dir(dx, dy)
                local key = loc.valid and LocKey(loc) or nil
                if key ~= nil and not seen[key] then
                    seen[key] = true
                    local info = reachable[key]
                    if info ~= nil and BubbleAt(loc) and ProvokePenalty(token, info.loc, adjacentNow) == 0 then
                        local caught = 0
                        for _,other in ipairs(enemies) do
                            if other:Distance(info.loc) <= 2 then
                                caught = caught + 1
                            end
                        end
                        local value = caught - (info.cost or 0)*0.001
                        if caught >= 2 and (best == nil or value > best.value) then
                            best = {loc = info.loc, caught = caught, value = value}
                        end
                    end
                end
            end
        end
    end
    if best == nil then
        return nil, "no reachable bubble square catches two enemies"
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Angulotl: Pop Noxious Bubble",
    category = "Maneuvers",
    --Not the needlers: they hold their perches on the trees and sand banks.
    monsters = {"Angulotl Slink", "Angulotl Wave", "Angulotl Daybringer"},
    abilities = {},
    description = "Hop into a wave's Noxious Bubble when bursting it catches two or more enemies; the angulotl comes out wet.",
    score = function(self, ai, token)
        if RemainingMovement(token) < 1 then
            return nil, "no movement left"
        end
        local plan, reason = FindBubblePopPlan(ai, token)
        if plan == nil then
            return nil, reason
        end
        if ai:MovementTokenIsAtLoc(token, plan.loc) then
            return nil, "already standing in the bubble"
        end
        plan.score = 1.35 + math.min(0.3, (plan.caught - 2)*0.1)
        return plan
    end,
    execute = function(self, ai, token, scoringInfo)
        ai:Speech(token, speech.popBubble)
        MoveCinematically(ai, token, scoringInfo.loc)
    end,
}

--------------------------------------------------------------------------------
-- Ranged angulotls keep their distance once their action is spent.
--------------------------------------------------------------------------------

local rangedAngulotls = {"Angulotl Needler", "Angulotl Wave", "Angulotl Slink"}

--The main action is spent when the signature strike can no longer be afforded.
local function MainActionSpent(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.categorization == "Signature Ability" and ability:HasKeyword("Strike") then
            return not ability:CanAfford(token)
        end
    end
    return true
end

--After shooting, a wet angulotl (immune to opportunity attacks) left next to
--an enemy hops back out of reach, still close enough to shoot next turn.
MonsterAI:RegisterMove{
    id = "Angulotl: Fall Back",
    category = "Maneuvers",
    monsters = rangedAngulotls,
    abilities = {},
    description = "Once the action is spent, a wet ranged angulotl next to an enemy moves out of reach without provoking.",
    score = function(self, ai, token)
        if not MainActionSpent(token) then
            return nil, "main action still available"
        end
        local enemies = LiveEnemies(ai)
        local adjacentNow = EnemiesAdjacentTo(token, enemies)
        if #adjacentNow == 0 then
            return nil, "no enemy adjacent"
        end
        if not DoesNotProvoke(token) then
            return nil, "leaving would provoke an opportunity attack"
        end
        local best = nil
        local bestScore = SkirmishScore(token, token.loc, enemies)
        for _,info in pairs(ai.paths or {}) do
            local _, adjacent = EnemyContact(enemies, info.loc)
            if adjacent == 0 and LandingIsFree(token, info.loc) and HazardAt(info.loc) == 0 then
                local score = SkirmishScore(token, info.loc, enemies) - (info.cost or 0)*0.001
                if score > bestScore then
                    best = info.loc
                    bestScore = score
                end
            end
        end
        if best == nil then
            return nil, "no better square in reach"
        end
        return {score = 0.3, loc = best}
    end,
    execute = function(self, ai, token, scoringInfo)
        MoveCinematically(ai, token, scoringInfo.loc)
    end,
}

--Once a ranged angulotl has attacked, nothing else scores and the framework's
--fallback would walk it toward the nearest enemy: down off a tree trunk or a
--sand bank and into melee. Scoring just above nothing keeps it where it is.
MonsterAI:RegisterMove{
    id = "Angulotl: Hold Range",
    category = "Maneuvers",
    monsters = rangedAngulotls,
    abilities = {},
    maxScore = 0.01,
    description = "A ranged angulotl with an enemy in range stays where it is instead of advancing into melee once it has nothing left to do.",
    score = function(self, ai, token)
        local reach = SignatureStrikeRange(token)
        if reach <= 1 then
            return nil, "not a ranged angulotl"
        end
        local pierceWalls = token.properties:GetPierceWalls()
        for _,enemy in ipairs(LiveEnemies(ai)) do
            if MonsterAI.TargetDistance(token, enemy) <= reach
                and token:GetLineOfSight(enemy, pierceWalls) > 0 then
                return {score = 0.01}
            end
        end
        return nil, "no enemy in range from here; advancing is fine"
    end,
    execute = function(self, ai, token, scoringInfo)
    end,
}

--------------------------------------------------------------------------------
-- Quick Snack: a non-minion angulotl eats an adjacent pollywog to heal.
--------------------------------------------------------------------------------

local function FindQuickSnackPlan(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local pollywogs = {}
    for _,ally in ipairs(ai.allyTokens or {}) do
        if LiveCreature(ally) and ally.charid ~= token.charid
            and ability:TargetPassesFilter(token, ally, {}) then
            pollywogs[#pollywogs+1] = ally
        end
    end
    if #pollywogs == 0 then
        return nil
    end

    local best = nil
    for _,info in pairs(ai.paths or {}) do
        for _,pollywog in ipairs(pollywogs) do
            if pollywog:Distance(info.loc) <= range
                and (best == nil or (info.cost or 0) < best.cost) then
                best = {loc = info.loc, target = pollywog, cost = info.cost or 0}
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Angulotl: Quick Snack",
    category = "Maneuvers",
    monsters = angulotlNonMinions,
    abilities = {"Quick Snack"},
    description = "Eat a nearby pollywog to regain 4 Stamina and become wet, when wounded enough to need it.",
    score = function(self, ai, token, ability)
        local missing = MissingStamina(token)
        if missing < 4 then
            return nil, "missing less than 4 Stamina"
        end
        local plan = FindQuickSnackPlan(ai, token, ability)
        if plan == nil then
            return nil, "no pollywog within reach this turn"
        end
        local urgency = math.min(1, missing / math.max(1, token.properties.max_hitpoints) * 2)
        plan.score = 0.55 + urgency*0.3
        return plan
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        if not LiveCreature(scoringInfo.target) then
            return
        end
        ai:Speech(token, speech.quickSnack)
        ai.Sleep(stationaryPause)
        ai:ExecuteAbility(token, ability, {{token = scoringInfo.target}}, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Angulotl Daybringer.
--------------------------------------------------------------------------------

--Acid Grasp's "1 Malice: Jump Before" mode: move, jump up to 3, then grasp up
--to two creatures next to the landing. Looks only at squares next to enemies.
local function FindAcidGraspJumpPlan(ai, token, ability)
    local jumpRange = 3
    local numTargets = ability:GetNumTargets(token)
    local enemies = LiveEnemies(ai)
    local checked = {}
    local candidates = {}

    for _,enemy in ipairs(enemies) do
        local ring = dmhub.CalculateShape{
            shape = "RadiusFromCreature",
            token = enemy,
            radius = 1,
            checklos = false,
        }
        for _,landing in ipairs(ring.locations or {}) do
            local key = LocKey(landing)
            if not checked[key] then
                checked[key] = true
                if LandingIsFree(token, landing) and MonsterAI.HoldPermits(token, landing) then
                    local targets = {}
                    for _,other in ipairs(enemies) do
                        if other:Distance(landing) <= 1 then
                            targets[#targets+1] = other
                        end
                    end
                    table.sort(targets, function(a, b)
                        return StrikeTargetScore(a, 0) > StrikeTargetScore(b, 0)
                    end)
                    table.resize_array(targets, numTargets)

                    local value = 0
                    for _,target in ipairs(targets) do
                        value = value + StrikeTargetScore(target, 0)
                    end

                    local bestFrom = nil
                    for _,info in pairs(ai.paths or {}) do
                        local cost = info.cost or 0
                        if info.loc:DistanceInTiles(landing) <= jumpRange
                            and (bestFrom == nil or cost < bestFrom.cost) then
                            bestFrom = {loc = info.loc, cost = cost}
                        end
                    end

                    if bestFrom ~= nil and #targets > 0 then
                        candidates[#candidates+1] = {
                            loc = bestFrom.loc,
                            landing = landing,
                            targets = targets,
                            value = value - bestFrom.cost*0.001,
                        }
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b) return a.value > b.value end)

    --Confirm line of sight from the landing for the strongest few.
    for i=1,math.min(6, #candidates) do
        local candidate = candidates[i]
        local visible = true
        ai:ExecuteWithTheoreticalMovementLoc(token, candidate.landing, function()
            for _,target in ipairs(candidate.targets) do
                if token:GetLineOfSight(target, token.properties:GetPierceWalls()) <= 0 then
                    visible = false
                end
            end
        end)
        if visible then
            return candidate
        end
    end
end

MonsterAI:RegisterMove{
    id = "Angulotl Daybringer: Acid Grasp",
    category = "Main Actions",
    monsters = {"Angulotl Daybringer"},
    abilities = {"Acid Grasp"},
    description = "Grasp two enemies; spend 1 Malice to jump in first when that reaches an extra target, or to jump clear afterwards when wet, badly hurt and surrounded.",
    score = function(self, ai, token, ability)
        local loc, value = ai:FindBestMoveToUseStrike(token, ability, StrikeTargetScore)
        if loc ~= nil and (value == nil or value <= 0) then
            loc = nil
        end

        local jumpPlan = nil
        if ability:CanAfford(token, {mode = 2}) then
            jumpPlan = FindAcidGraspJumpPlan(ai, token, ability)
            if jumpPlan ~= nil and loc ~= nil and jumpPlan.value < value + 0.8 then
                jumpPlan = nil
            end
        end

        if jumpPlan ~= nil then
            return {
                score = 1.3,
                mode = 2,
                loc = jumpPlan.loc,
                landing = jumpPlan.landing,
                targets = jumpPlan.targets,
            }
        end

        if loc == nil then
            return nil, "no enemy can be grasped this turn"
        end

        --Jumping away provokes opportunity attacks unless the daybringer is immune (wet).
        --A daybringer holding a post (the Ritual Basin's ward) stays on it instead.
        local mode = 1
        if StaminaFraction(token) < 0.5 and DoesNotProvoke(token) and ability:CanAfford(token, {mode = 3})
            and not MonsterAI.Holds(token) then
            local _, adjacent = EnemyContact(LiveEnemies(ai), loc)
            if adjacent >= 2 then
                mode = 3
            end
        end
        return {
            score = 1.1 + math.min(0.2, math.max(0, value - 1)*0.2),
            mode = mode,
            loc = loc,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)

        if scoringInfo.mode == 2 then
            local targets = {}
            for _,target in ipairs(scoringInfo.targets or {}) do
                if LiveCreature(target) then
                    targets[#targets+1] = {token = target}
                end
            end
            ai:SetTargetsForExpectedPrompt{
                casterid = token.charid,
                targets = targets,
                sleep = stationaryPause,
            }
            ShowJump(token, scoringInfo.landing)
            ai:ExecuteAbility(token, ability:SwitchModes(2), {{loc = scoringInfo.landing}}, {
                sleep = abilityPause,
                symbols = {mode = 2},
            })
            ai._tmp_expectedPromptTarget = nil
            return
        end

        local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, StrikeTargetScore)
        ai:ExecuteAbility(token, ability:SwitchModes(scoringInfo.mode), targets, {
            sleep = abilityPause,
            symbols = {mode = scoringInfo.mode},
        })
    end,
}

--Fallback for Jump Before's strike when the planned targets were not used.
MonsterAI:RegisterPrompt{
    prompts = {"Angulotl Daybringer:Acid Grasp - Copy"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties)
        local targets = {}
        for _,enemy in ipairs(HostileCreatures(casterToken)) do
            if MonsterAI.TargetDistance(casterToken, enemy) <= range
                and abilityClone:TargetPassesFilter(casterToken, enemy, symbols) then
                targets[#targets+1] = {token = enemy}
            end
        end
        table.sort(targets, function(a, b)
            return StrikeTargetScore(a.token, 0) > StrikeTargetScore(b.token, 0)
        end)
        table.resize_array(targets, abilityClone:GetNumTargets(casterToken))
        return {targets = targets}
    end,
}

--The daybringer's own jumps (Acid Grasp's Jump After) clear away from the
--fight; allies jumping through Plague of Frogs use the plan made for them.
MonsterAI:RegisterPrompt{
    prompts = {"Angulotl Daybringer:Jump"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        --Plague of Frogs is resolving while plans exist; its free strike follows.
        local purpose = "engage"
        if casterToken.charid == invokerToken.charid
            and ai:try_get("_tmp_angulotlJumpPlans") == nil then
            purpose = "skirmish"
        end
        return AnswerJumpPrompt(ai, casterToken, abilityClone, purpose)
    end,
}

--Any other angulotl's jump with no plan: get into a fighting position.
local otherJumpPrompts = {}
for _,monsterType in ipairs(angulotlMonsters) do
    if monsterType ~= "Angulotl Daybringer" then
        otherJumpPrompts[#otherJumpPrompts+1] = monsterType .. ":Jump"
    end
end

MonsterAI:RegisterPrompt{
    prompts = otherJumpPrompts,
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return AnswerJumpPrompt(ai, casterToken, abilityClone, "engage")
    end,
}

local function SunLampBeneficiaries(token)
    local count = 0
    local value = 0
    for _,ally in ipairs(FriendlyAngulotls(token)) do
        if token:Distance(ally) <= 10 then
            count = count + 1
            local heal = math.min(5, MissingStamina(ally)) / 5
            value = value + cond(IsMinion(ally), 0.4, 1) + cond(IsMinion(ally), 0, heal*0.6)
        end
    end
    return count, value
end

MonsterAI:RegisterMove{
    id = "Angulotl Daybringer: Sun Lamp",
    category = "Maneuvers",
    monsters = {"Angulotl Daybringer"},
    abilities = {"Sun Lamp"},
    description = "Shine when at least two angulotls (counting the daybringer) are within 10 squares to heal and speed them.",
    score = function(self, ai, token, ability)
        if HasOngoingEffect(token, sunLampEffectId) then
            return nil, "Sun Lamp is already shining"
        end
        local count, value = SunLampBeneficiaries(token)
        if count < 2 then
            return nil, "fewer than two angulotls within 10 squares"
        end
        return {score = 0.7 + math.min(0.2, value*0.02), beneficiaries = count}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:Speech(token, speech.sunLamp)
        ai.Sleep(stationaryPause)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

local function TriggerTargets(triggerInfo)
    local result = {}
    for _,charid in ipairs(triggerInfo.targets or {}) do
        local target = FindTokenByCharid(charid)
        if LiveCreature(target) then
            result[#result+1] = target
        end
    end
    return result
end

MonsterAI:RegisterTrigger{
    id = "Angulotl Daybringer: Tongue Slap",
    monsters = {"Angulotl Daybringer"},
    abilities = {"Tongue Slap"},
    triggers = {"Tongue Slap"},
    description = "Reduce a strike's tier when it targets the daybringer or a non-minion ally; let strikes on minions through.",
    handler = function(ai, token, triggerInfo)
        local friends = 0
        local protectsNonMinion = false
        for _,target in ipairs(TriggerTargets(triggerInfo)) do
            if target:IsFriend(token) then
                friends = friends + 1
                if target.charid == token.charid or not IsMinion(target) then
                    protectsNonMinion = true
                end
            end
        end
        if friends > 0 and not protectsNonMinion then
            return {dismiss = true}
        end
        return {activate = true}
    end,
}

--Moisturizing End Effect's free option: the adjacent wet creature to dry.
--Friends first (non-angulotls, then minions, then other angulotls), a hero
--last: a wet hero takes It Is Day's 6 acid and can slip prone.
local function MoisturizingDonor(token)
    local best, bestRank = nil, nil
    for _,other in ipairs(dmhub.allTokens) do
        if other.charid ~= token.charid and LiveCreature(other) and IsWet(other)
            and MonsterAI.TargetDistance(token, other) <= 1 then
            local rank = 4
            if other:IsFriend(token) then
                if not IsAngulotl(other) then
                    rank = 1
                elseif IsMinion(other) then
                    rank = 2
                else
                    rank = 3
                end
            end
            if bestRank == nil or rank < bestRank then
                best, bestRank = other, rank
            end
        end
    end
    return best
end

MonsterAI:RegisterTrigger{
    id = "Angulotl Daybringer: Moisturizing End Effect",
    monsters = {"Angulotl Daybringer"},
    abilities = {"End Effect"},
    description = "End a bad save-ends effect by drying an adjacent wet creature (allies before heroes) when one is there, otherwise by taking 5 damage when it can spare the Stamina.",
    handler = function(ai, token, triggerInfo)
        local worst, purge = MonsterAI.EndEffectSeverity(token, triggerInfo)
        local donor = MoisturizingDonor(token)
        local decision, reason
        if purge ~= nil and donor ~= nil and worst >= MonsterAI.endEffectMinimumSeverity then
            decision = {activate = true, mode = 2}
            reason = string.format("ending severity %d by drying %s", worst, MonsterAI.TokenLogName(donor))
        else
            decision, reason = MonsterAI.EndEffectDecision(token, triggerInfo)
        end
        local result = "Director decision"
        local mode = nil
        if decision ~= nil then
            result = cond(decision.activate, "activate", "dismiss")
            mode = decision.mode
        end
        ai:LogDecision("END EFFECT", {
            ability = triggerInfo.abilityName,
            result = result,
            mode = mode,
            reason = reason,
        })
        return decision
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Angulotl Daybringer:Moisturizing End Effect"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local donor = MoisturizingDonor(casterToken)
        if donor == nil then
            return {targets = {}}
        end
        return {targets = {{token = donor}}}
    end,
}

--------------------------------------------------------------------------------
-- Daybringer villain actions.
--------------------------------------------------------------------------------

local function NewDawnSquareScore(token, loc, enemies, wounded)
    local nearest, adjacent = EnemyContact(enemies, loc)
    local score = cond(adjacent > 0, 2, 0) - nearest*0.3 - math.max(0, adjacent - 2)*0.5
    for _,ally in ipairs(wounded) do
        if ally:Distance(loc) <= 1 then
            score = score + 1
            break
        end
    end
    return score
end

local function FindNewDawnSquares(ai, token, ability)
    local count = ability:GetNumTargets(token)
    local range = ability:GetRange(token.properties)
    local enemies = LiveEnemies(ai)
    local wounded = {}
    for _,ally in ipairs(FriendlyAngulotls(token)) do
        if not IsMinion(ally) and MissingStamina(ally) >= 4 then
            wounded[#wounded+1] = ally
        end
    end

    local scored = {}
    for _,loc in ipairs(LandingCandidates(token, range)) do
        scored[#scored+1] = {loc = loc, score = NewDawnSquareScore(token, loc, enemies, wounded)}
    end
    table.sort(scored, function(a, b) return a.score > b.score end)

    --Pollywogs are size 1S, so one square each; skip squares already chosen.
    local chosen = {}
    local reserved = {}
    for _,entry in ipairs(scored) do
        if #chosen >= count then
            break
        end
        local key = LocKey(entry.loc)
        if not reserved[key] then
            reserved[key] = true
            chosen[#chosen+1] = {loc = entry.loc}
        end
    end
    return chosen
end

MonsterAI:RegisterVillainAction{
    id = "Angulotl Daybringer: New Dawn",
    monsters = {"Angulotl Daybringer"},
    abilities = {"New Dawn"},
    description = "Hatch four pollywogs beside enemies and wounded angulotls who can eat them.",
    score = function(self, ai, token, ability, context)
        local squares = FindNewDawnSquares(ai, token, ability)
        if #squares == 0 then
            return nil, "no unoccupied squares within distance"
        end
        return {score = math.min(1, 0.6 + #squares*0.08), squares = #squares}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local squares = FindNewDawnSquares(ai, token, ability)
        if #squares == 0 then
            return
        end
        ai:Speech(token, speech.newDawn)
        ai.Sleep(abilityPause)
        ai:ExecuteAbility(token, ability, squares, {sleep = abilityPause})
    end,
}

--Plans each creature's jump for Plague of Frogs: non-minions land where they
--can free strike, minions where they threaten an enemy for their next turn.
local function PlanPlagueOfFrogs(ai, token, ability)
    local range = ability:GetRange(token.properties)
    local enemies = LiveEnemies(ai)
    local reserved = {}
    local plans = {}
    local strikers = 0

    local jumpers = {}
    for _,ally in ipairs(ai.allyTokens or {}) do
        if LiveCreature(ally) and token:Distance(ally) <= range
            and ability:TargetPassesFilter(token, ally, {}) then
            jumpers[#jumpers+1] = ally
        end
    end
    --Non-minions pick first: their landing also earns a free strike.
    table.sort(jumpers, function(a, b)
        return cond(IsMinion(a), 1, 0) < cond(IsMinion(b), 1, 0)
    end)

    for _,ally in ipairs(jumpers) do
        local loc, score = FindBestLanding(ally, 4, "engage", enemies, reserved)
        if loc ~= nil and score ~= nil and score > CurrentLandingScore(ally, "engage", enemies) then
            plans[ally.charid] = loc
            ReserveLanding(ally, loc, reserved)
            local nearest = EnemyContact(enemies, loc)
            if not IsMinion(ally) and nearest <= SignatureStrikeRange(ally) then
                strikers = strikers + 1
            end
        else
            ReserveLanding(ally, ally.loc, reserved)
            local nearest = EnemyContact(enemies, ally.loc)
            if not IsMinion(ally) and nearest <= 1 then
                strikers = strikers + 1
            end
        end
    end
    return plans, #jumpers, strikers
end

--Plague of Frogs' free strike arrives as the standard "Make Free Strike"
--wrapper. Reuse the shared free strike chooser; skip when nothing is in reach.
MonsterAI:RegisterPrompt{
    prompts = {"Angulotl Daybringer:Make Free Strike"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local generic = MonsterAI.prompts["Free Strike"]
        local result = nil
        if generic ~= nil then
            result = generic.handler(ai, invokerToken, casterToken, abilityClone, symbols, options)
        end
        return result or {targets = {}}
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Angulotl Daybringer: Plague of Frogs",
    monsters = {"Angulotl Daybringer"},
    abilities = {"Plague of Frogs"},
    description = "Every angulotl within 8 squares jumps into the fight; non-minions free strike on landing.",
    score = function(self, ai, token, ability, context)
        local plans, jumpers, strikers = PlanPlagueOfFrogs(ai, token, ability)
        local moving = #table.keys(plans)
        if moving == 0 and strikers == 0 then
            return nil, "no ally gains anything from jumping"
        end
        return {
            score = math.min(1, 0.5 + strikers*0.12 + moving*0.04),
            jumpers = jumpers,
            strikers = strikers,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local plans = PlanPlagueOfFrogs(ai, token, ability)
        ai._tmp_angulotlJumpPlans = plans

        --The jumps and free strikes are prompted on each ally, so the AI must
        --answer for every creature in the burst while the action resolves.
        local controls = {}
        for _,ally in ipairs(ai.allyTokens or {}) do
            if LiveCreature(ally) and ally.charid ~= token.charid
                and token:Distance(ally) <= ability:GetRange(token.properties) then
                controls[#controls+1] = {token = ally, info = ai:BeginTokenControl(ally)}
            end
        end

        ai:Speech(token, speech.plagueOfFrogs)
        ai.Sleep(abilityPause)
        local ok, err = ai:RunYieldingFunction(function()
            ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        end)

        for _,control in ipairs(controls) do
            pcall(function()
                ai:EndTokenControl(control.token, control.info)
            end)
        end
        ai._tmp_angulotlJumpPlans = nil
        if not ok then
            error(err)
        end
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Angulotl Daybringer: It Is Day",
    monsters = {"Angulotl Daybringer"},
    abilities = {"It Is Day"},
    description = "Dry the map: burn every wet enemy for 6 acid, illuminate enemies, and give every angulotl a double edge.",
    score = function(self, ai, token, ability, context)
        local enemies = LiveEnemies(ai)
        if #enemies == 0 then
            return nil, "no enemies"
        end
        local wet = 0
        for _,enemy in ipairs(enemies) do
            if IsWet(enemy) then
                wet = wet + 1
            end
        end
        local angulotls = #FriendlyAngulotls(token)
        return {
            score = math.min(1, 0.45 + wet*0.12 + math.min(6, angulotls)*0.03),
            wetEnemies = wet,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.itIsDay)
        ai.Sleep(abilityPause)
        ExecuteMapAbility(ai, token, ability)
    end,
}

--------------------------------------------------------------------------------
-- Leapfrog trigger: an inactive angulotl jumps 3 when another moves through it.
--------------------------------------------------------------------------------

MonsterAI:RegisterTrigger{
    id = "Angulotl: Leapfrog",
    monsters = angulotlMonsters,
    abilities = {"Leapfrog"},
    description = "Jump up to 3 squares toward a better fighting position when a friend hops through.",
    handler = function(ai, token, triggerInfo)
        local enemies = HostileCreatures(token)
        if #enemies == 0 then
            return {dismiss = true}
        end
        local range = math.min(3, token.properties:CurrentMovementSpeed())
        local loc, score = FindBestLanding(token, range, "engage", enemies)
        if loc == nil or score == nil
            or score < CurrentLandingScore(token, "engage", enemies) + 0.5 then
            return {dismiss = true}
        end
        return {
            activate = true,
            expectedPrompt = {
                targets = {{loc = loc}},
                sleep = movementPause,
            },
        }
    end,
}

--------------------------------------------------------------------------------
-- Start-of-turn Angulotl Malice features.
--------------------------------------------------------------------------------

MonsterAI:RegisterMaliceAbility{
    id = "Angulotl Malice: Leapfrog",
    monsterGroups = angulotlGroup,
    abilities = {"Leapfrog"},
    description = "Spend 3 Malice while a large clutch is still closing in, so inactive angulotls can leap forward as others pass through them.",
    score = function(self, ai, token, ability, context)
        local enemies = context.enemyTokens or {}
        if #enemies == 0 then
            return nil
        end
        local acting = {}
        for _,actor in ipairs(context.actingTokens or {}) do
            acting[actor.charid] = true
        end

        --Spend nothing when the feature's own filter would reach no angulotl.
        local affected = 0
        for _,ally in ipairs(FriendlyAngulotls(token)) do
            if ability:TargetPassesFilter(token, ally, {}) then
                affected = affected + 1
            end
        end
        if affected < 2 then
            return nil, "the Leapfrog effect's target filter matches fewer than two angulotls"
        end

        local movers = 0
        local inactive = 0
        for _,ally in ipairs(FriendlyAngulotls(token)) do
            local nearest = EnemyContact(enemies, ally.loc)
            if acting[ally.charid] then
                if nearest > 1 then
                    movers = movers + 1
                end
            elseif nearest > 2 then
                inactive = inactive + 1
            end
        end
        if movers < 2 or inactive < 3 then
            return nil, "too few angulotls still closing on the enemy"
        end
        return {
            score = math.min(0.75, 0.5 + math.min(6, inactive)*0.025 + math.min(4, movers)*0.025),
            movers = movers,
            inactive = inactive,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.leapfrog)
        ai.Sleep(stationaryPause)
        ExecuteMapAbility(ai, token, ability)
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Angulotl Malice: Resonating Croak",
    monsterGroups = angulotlGroup,
    abilities = {"Resonating Croak"},
    description = "Spend 5 Malice when at least two enemies are next to an angulotl; each non-angulotl ally it would catch lowers the score.",
    score = function(self, ai, token, ability, context)
        local enemies, allies = 0, 0
        for _,target in ipairs(dmhub.allTokens) do
            if LiveCreature(target) and ability:TargetPassesFilter(token, target, {}) then
                if target:IsFriend(token) then
                    allies = allies + 1
                else
                    enemies = enemies + 1
                end
            end
        end
        if enemies < 2 then
            return nil, "fewer than two enemies are next to an angulotl"
        end
        return {
            score = math.min(0.95, 0.62 + enemies*0.07 - allies*0.15),
            enemies = enemies,
            allies = allies,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.resonatingCroak)
        ai.Sleep(stationaryPause)
        ExecuteMapAbility(ai, token, ability)
    end,
}

local function DaybringerCanStillUseItIsDay(token)
    for _,ally in ipairs(FriendlyAngulotls(token)) do
        if MonsterType(ally) == "Angulotl Daybringer" then
            local itIsDay = FindAbility(ally, "It Is Day")
            local slot = itIsDay ~= nil and itIsDay:try_get("villainAction") or nil
            if itIsDay ~= nil and (slot == nil or not VillainActionState.HasUsed(ally.charid, slot)) then
                return true
            end
        end
    end
    return false
end

--Rainfall only soaks creatures exposed to the sky (not under a ceiling or a
--Tree Canopy zone). Unreadable symbol = assume exposed, as most maps are open.
local function ExposedToSky(token)
    local exposed = true
    pcall(function()
        exposed = creature.lookupSymbols["exposedtosky"](token.properties) == true
    end)
    return exposed
end

--The Malice Rainfall costs this caster right now. Encounter rules and zones
--discount it (Aixco Hollow: 5 while a wave lives, 3 at the ritual basin).
local function MaliceCost(token, ability)
    local cost = 7
    pcall(function()
        local details = ability:GetCost(token).details
        local quantity = details ~= nil and details[1] ~= nil and tonumber(details[1].quantity) or nil
        if quantity ~= nil then
            cost = quantity
        end
    end)
    return cost
end

MonsterAI:RegisterMaliceAbility{
    id = "Angulotl Malice: Rainfall",
    monsterGroups = angulotlGroup,
    abilities = {"Rainfall"},
    description = "Spend Malice to soak the encounter when dry enemies and dry angulotls are under open sky, especially alongside clawfish, a daybringer saving It Is Day, or when an encounter makes it cheaper.",
    score = function(self, ai, token, ability, context)
        --Wet enemies slip prone when they end a turn with no movement left (and
        --clawfish shock them); wet angulotls move without provoking opportunity
        --attacks. Both sides get soaked, so both count.
        local dryEnemies = 0
        for _,enemy in ipairs(context.enemyTokens or {}) do
            if LiveCreature(enemy) and not IsWet(enemy) and ExposedToSky(enemy) then
                dryEnemies = dryEnemies + 1
            end
        end

        local dryAllies = 0
        local clawfish = 0
        for _,ally in ipairs(FriendlyAngulotls(token)) do
            if MonsterType(ally) == "Clawfish" then
                clawfish = clawfish + 1
            end
            if not IsWet(ally) and ExposedToSky(ally) then
                dryAllies = dryAllies + 1
            end
        end

        if dryEnemies == 0 then
            return nil, "no dry enemy is exposed to the sky"
        end
        if dryEnemies < 2 and dryAllies < 4 then
            return nil, "too few dry creatures are exposed to the sky"
        end

        local cost = MaliceCost(token, ability)
        local discount = math.max(0, 7 - cost)
        local itIsDay = DaybringerCanStillUseItIsDay(token)
        return {
            score = math.min(0.95, 0.5 + math.min(5, dryEnemies)*0.05 + math.min(6, dryAllies)*0.02
                + math.min(4, clawfish)*0.04 + cond(itIsDay, 0.12, 0) + discount*0.02),
            dryEnemies = dryEnemies,
            dryAllies = dryAllies,
            clawfish = clawfish,
            cost = cost,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:Speech(token, speech.rainfall)
        ai.Sleep(stationaryPause)
        ExecuteMapAbility(ai, token, ability)
    end,
}
