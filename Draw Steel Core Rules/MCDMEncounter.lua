local mod = dmhub.GetModLoading()

-- This file defines the Encounter game type (the authored definition of an
-- encounter: which monsters/groups it contains and how it scales with the number
-- of heroes) and the LiveEncounter game type (the state of an encounter that is
-- currently running inside an initiative queue).
--
-- The Encounter type used to live in Draw Steel V/EncounterPanel.lua. The data /
-- rules portion was moved here so that LiveEncounter -- which starts life as a
-- copy of Encounter -- can be defined alongside it. The encounter-creator UI
-- methods (Encounter.Editor / Encounter.CreateEditorDialog) remain in
-- EncounterPanel.lua, since they are UI concerns and depend on that file's
-- local panel helpers.

local g_numHeroesSetting = setting {
    id = "numheroes",
    description = "Number of Heroes",
    help = "This setting will guide balance of encounters you create.",
    section = "game",
    editor = "dropdown",
    default = 4,
    enum = {
        {
            value = 3,
            text = "Three Heroes",
        },
        {
            value = 4,
            text = "Four Heroes",
        },
        {
            value = 5,
            text = "Five Heroes",
        },
        {
            value = 6,
            text = "Six Heroes",
        },
        {
            value = 7,
            text = "Seven Heroes",
        },
    }
}

Encounter = RegisterGameType('Encounter')

Encounter.name = 'New Encounter'

--Optional free-text notes about the encounter, edited in the encounter builder.
Encounter.description = ''

Encounter.tableName = 'encounters'

Encounter.monsters = {}

Encounter.groups = {}

--Additional waves an encounter can spawn after the start. Each entry is a table:
--  id    : string   stable guid used to reference the wave from a group
--  name  : string   display name
--  round : number|string   the round the wave arrives on (2-6), or "every" for
--                          "Every round". A group with no wave assigned (group.wave
--                          == nil) arrives at the start of the encounter.
--By default an encounter has no additional waves.
Encounter.waves = {}

--The condition under which the encounter counts as won. Stored as one of the ids
--from Encounter.GetVictoryConditions(); defaults to "all_defeated".
Encounter.victoryCondition = "all_defeated"

--When victoryCondition == "destroy_thing", the object keyword identifying the
--"thing" the heroes must destroy. Chosen from the Targetable objects on the map.
Encounter.victoryDestroyKeyword = nil

--The number of Victories each hero earns for winning this encounter. Awarded from the
--victory screen (DSVictoryScreen). Defaults to 1.
Encounter.victories = 1

--The named encounter rule-sets attached to this encounter, stored as a set of EncounterRuleSet
--ids ({[id]=true}; authored in the compendium under Rules -> Encounter Rules). Activating these
--rules while the encounter is running is a future phase; for now this just stores the attachments.
Encounter.ruleSets = {}

--Returns the lowercase organization keyword (the first word of a creature's role, e.g.
--"Leader Controller" -> "leader") for any creature/monster properties, or nil. Read via
--try_get + regex so it is safe on plain creature-typed properties: monster:Organization()
--is absent on some compendium monster assets whose properties are creature-typed, and
--reading a missing method raises rather than returning nil. Mirrors monster:Organization().
local function OrganizationKeyword(props)
    if props == nil then
        return nil
    end
    local m = regex.MatchGroups(props:try_get("role", ""), "^(?<org>[a-zA-Z]+).*$")
    if m ~= nil then
        return string.lower(m.org)
    end
    return nil
end

--The selectable victory conditions for an encounter (id + display text).
function Encounter.GetVictoryConditions(encounter)
    local result = {
        { id = "all_defeated", text = "All Monsters Defeated" },
        { id = "heroes_outnumber", text = "Heroes Outnumber Monsters" },
        { id = "heroes_outnumber_two_to_one", text = "Heroes Outnumber Monsters Two-to-One" },
        { id = "half_defeated", text = "Half Monsters Defeated" },
        { id = "solo_exhausted", text = "Solo Exhausted" },
        { id = "destroy_thing", text = "Destroy the Thing!" },
    }

    --"Leader Defeated" is only offered when the encounter actually contains a Leader
    --monster (the objective tracks that leader's Stamina on the boss bar and wins when it
    --falls). It is also kept available when already selected, so a previously-configured
    --encounter whose leader was since removed still shows its chosen value rather than a
    --blank dropdown.
    if encounter ~= nil and (Encounter.HasMonsterWithOrganization(encounter, "leader") or
        encounter:try_get("victoryCondition") == "leader_defeated") then
        result[#result + 1] = { id = "leader_defeated", text = "Leader Defeated" }
    end

    return result
end

-- Returns true if the (design-time) encounter contains at least one monster whose
-- organization matches the given lowercase keyword (e.g. "leader", "solo"). Scans every
-- group's monster roster against the monster compendium assets. Used to gate the
-- "Leader Defeated" victory condition in the encounter editor.
function Encounter.HasMonsterWithOrganization(encounter, org)
    if encounter == nil then
        return false
    end
    for _, group in ipairs(encounter:try_get("groups", {})) do
        for monsterid, quantity in pairs(group.monsters or {}) do
            if quantity ~= nil and quantity > 0 then
                local monster = assets.monsters[monsterid]
                if monster ~= nil and monster.properties ~= nil and OrganizationKeyword(monster.properties) == org then
                    return true
                end
            end
        end
    end
    return false
end

--Scans the current map for objects that have the Targetable property and returns a
--sorted list of the distinct keywords found on them. Used by the "Destroy the Thing!"
--victory condition to let the DM pick which object the heroes must destroy.
function Encounter.GetTargetableObjectKeywords()
    local seen = {}
    for _, token in ipairs(dmhub.allTokensIncludingObjects) do
        if token.valid and token.isObject then
            local component = token.objectComponent
            if component ~= nil and component.componentType == "LuaTargetableObject" then
                local levelObject = component.levelObject
                if levelObject ~= nil and levelObject.keywords ~= nil then
                    for keyword, _ in pairs(levelObject.keywords) do
                        seen[keyword] = true
                    end
                end
            end
        end
    end

    local result = {}
    for keyword, _ in pairs(seen) do
        result[#result + 1] = keyword
    end
    table.sort(result)
    return result
end

--Returns the list of Targetable object tokens currently on the map whose keywords include
--the given keyword. Objects that have been removed from the map are simply absent from
--this list. Used by the "Destroy the Thing!" victory condition and boss bar.
function Encounter.GetTargetableObjectsWithKeyword(keyword)
    local result = {}
    if keyword == nil or keyword == "" then
        return result
    end

    for _, token in ipairs(dmhub.allTokensIncludingObjects) do
        if token.valid and token.isObject then
            local component = token.objectComponent
            if component ~= nil and component.componentType == "LuaTargetableObject" then
                local levelObject = component.levelObject
                if levelObject ~= nil and levelObject.keywords ~= nil and levelObject.keywords[keyword] then
                    result[#result + 1] = token
                end
            end
        end
    end

    return result
end

--Returns the display name to show for a boss-bar token. Object tokens carry their renamed
--per-instance name on the level object (token.name is just the underlying asset/blueprint
--name, e.g. "skull3"), so prefer that; everything else uses the standard token name.
function Encounter.GetBossTokenName(token)
    if token == nil then
        return ""
    end

    if token.isObject then
        local component = token.objectComponent
        if component ~= nil then
            local levelObject = component.levelObject
            if levelObject ~= nil then
                local name = levelObject.name
                if name ~= nil and name ~= "" then
                    return name
                end
            end
        end
    end

    return creature.GetTokenDescription(token)
end

--if true, then when saving an encounter, we save the appearance of the monsters.
Encounter.saveAppearances = false

function Encounter.AddWave(self)
    self.waves = DeepCopy(self.waves)
    self.waves[#self.waves + 1] = {
        id = dmhub.GenerateGuid(),
        name = "Reinforcements",
        round = 2,
    }
    return self.waves[#self.waves]
end

--Human-readable description of when a wave arrives, e.g. "Round 2" or "Every round".
function Encounter.WaveRoundText(wave)
    if wave.round == "every" then
        return "Every round"
    end
    return string.format("Round %d", wave.round)
end

--Scene cues an encounter can carry: authored moments that surface a
--Director banner in the initiative bar when their round arrives (a floor
--collapse, a building demolition, competitive demons breaking rank...).
--Unlike waves they spawn nothing themselves; firing one is a Director
--action the banner walks through. Each entry is a table:
--  id    : string   stable guid
--  name  : string   display name, e.g. "The Floor Collapses"
--  round : number|string  the round the banner becomes available (2-6), or
--                         "every" -- same semantics as wave rounds.
--  text  : string   Director-facing summary of what happens on firing.
--  check : nil|table  optional one-tap group test the banner can launch:
--      { title: string, characteristics: {attrid=true,...}, tiers: {t1,t2,t3} }
--  steps : nil|list  optional ordered walkthrough rendered in the fire popup.
--      Each step is { type, ... }:
--        { type = "note",        text }  -- a manual checklist line
--        { type = "activations", text }  -- like note, plus a live count of
--                                        -- heroes who have not yet acted
--        { type = "grouptest",   title, characteristics, tiers }
--                                        -- one-tap pre-filled Request Rolls
--        { type = "malice",      value, text }  -- one-tap set Malice to value
--        { type = "opendoc",     docid, text }  -- open a journal page
Encounter.cues = {}

--Human-readable description of when a cue fires. Cues share wave
--round semantics.
function Encounter.CueRoundText(cue)
    return Encounter.WaveRoundText(cue)
end

--Encounter scripts attached to this encounter: a list of EncounterScriptInstance
--(see the Encounter Scripts section at the bottom of this file). Each instance
--references a script from the encounterScripts library (or carries inline custom
--Lua) plus the director's chosen parameter values. When the encounter goes live
--the instances deep-copy into the LiveEncounter and are driven by the
--encounter-script runtime on the elected host director's client.
Encounter.scripts = {}

function Encounter.MainMonster(encounter)
    local mainmonster = nil
    for i, group in ipairs(encounter.groups) do
        for monsterid, value in pairs(group.monsters) do
            local monster = assets.monsters[monsterid]
            if mainmonster == nil or monster.properties:EV() > mainmonster.properties:EV() then
                mainmonster = monster
            end
        end
    end

    return mainmonster
end

--Returns the number of monsters of the given type that should actually be placed
--for a group at a given number of heroes, applying the monster's "appears at N+
--heroes" gate (group.monsterMinHeroes[monsterid]) and any per-monster-type
--balancing adjustment configured on the group. Clamped to >= 0. This is the
--single source of truth shared by CloneForNumberOfHeroes (placement/EV/describe)
--and RichEncounter's despawn index walk, so spawn and despawn stay aligned.
function Encounter.AdjustedMonsterQuantity(group, monsterid, baseQuantity, numHeroes)
    --per-monster "appears at N+ heroes" gate: below the gate the monster
    --contributes nothing, regardless of balancing deltas.
    local monsterMinHeroes = group.monsterMinHeroes
    if monsterMinHeroes ~= nil and monsterMinHeroes[monsterid] ~= nil and numHeroes < monsterMinHeroes[monsterid] then
        return 0
    end

    local balancing = group.balancing
    local heroBalancing = balancing ~= nil and balancing[numHeroes] or nil
    if heroBalancing ~= nil and heroBalancing.monsters ~= nil then
        local delta = heroBalancing.monsters[monsterid]
        if type(delta) == "number" and delta ~= 0 then
            local quantity = baseQuantity + delta
            if quantity < 0 then
                quantity = 0
            end
            return quantity
        end
    end
    return baseQuantity
end

function Encounter.CloneForNumberOfHeroes(self, numHeroes)
    numHeroes = numHeroes or g_numHeroesSetting:Get()
    local encounter = DeepCopy(self)
    for i = #encounter.groups, 1, -1 do
        local group = encounter.groups[i]
        if group.minHeroes ~= nil and group.minHeroes > numHeroes then
            table.remove(encounter.groups, i)
        else
            --apply per-monster-type count adjustments configured for this number of heroes.
            local monsterids = {}
            for monsterid, _ in pairs(group.monsters) do
                monsterids[#monsterids + 1] = monsterid
            end

            for _, monsterid in ipairs(monsterids) do
                local quantity = Encounter.AdjustedMonsterQuantity(group, monsterid, group.monsters[monsterid], numHeroes)
                if quantity <= 0 then
                    group.monsters[monsterid] = nil
                else
                    group.monsters[monsterid] = quantity
                end
            end
        end
    end

    return encounter
end

function Encounter.AddMonster(self, monsterid)
    self.monsters = DeepCopy(self.monsters)
    self.monsters[monsterid] = (self.monsters[monsterid] or 0) + 1
end

function Encounter.AddGroup(self)
    self.groups = DeepCopy(self.groups)
    self.groups[#self.groups + 1] = { monsters = {} }
end

function Encounter.CountEDS(self)
    local EDSTotal = 0

    for i, group in ipairs(self.groups) do
        for monsterid, quantity in pairs(group.monsters) do
            local monster = assets.monsters[monsterid]

            if monster.properties.minion then
                EDSTotal = EDSTotal + round((assets.monsters[monsterid].properties:EV() * quantity) / 4)
            else
                EDSTotal = EDSTotal + (assets.monsters[monsterid].properties:EV() * quantity)
            end
        end
    end

    return EDSTotal
end

-- ===========================================================================
-- Encounter strength / difficulty budget
--
-- The Draw Steel encounter budget: each hero contributes an Encounter Strength
-- of 4 + 2 x level, and every 2 average Victories the party carries add one
-- "virtual hero" of average strength to the budget. A monster roster's EV total
-- is classified against that budget into the difficulty tiers below. This is
-- the single source of truth used by both the encounter builder (budget meter)
-- and the combat setup dialog (DSInitiativeRoll.lua).
-- ===========================================================================

--The ordered difficulty tiers, weakest to strongest.
Encounter.DifficultyTiers = { "Trivial", "Easy", "Standard", "Hard", "Extreme" }

--The encounter strength contributed by a single hero of the given level.
function Encounter.HeroStrength(level)
    return 4 + (level or 1) * 2
end

--Compute a party's encounter strength from explicit party parameters:
--  numHeroes : number of heroes (defaults to the "numheroes" setting)
--  level     : the party's level (defaults to 1)
--  victories : the party's average Victories per hero (defaults to 0)
--Returns a strength table:
--  total        : the party's total encounter strength (the standard budget)
--  base         : strength before the victories bonus
--  singleHero   : encounter strength of a single (average) hero
--  victoryBonus : strength added by victories (floor(victories/2) virtual heroes)
--  victoryHeroes: how many virtual heroes the victories added
--  numHeroes    : the hero count used
function Encounter.PartyStrength(args)
    args = args or {}
    local numHeroes = args.numHeroes or g_numHeroesSetting:Get()
    local singleHero = Encounter.HeroStrength(args.level)
    local base = singleHero * numHeroes
    local victoryHeroes = math.floor((args.victories or 0) / 2)
    local victoryBonus = victoryHeroes * singleHero
    return {
        total = base + victoryBonus,
        base = base,
        singleHero = singleHero,
        victoryBonus = victoryBonus,
        victoryHeroes = victoryHeroes,
        numHeroes = numHeroes,
    }
end

--Compute a party's encounter strength from a list of hero/ally tokens (each
--contributing 4 + 2 x their level; victories are averaged across the tokens).
--Returns nil when the list is empty; otherwise a strength table as in
--PartyStrength, plus:
--  numTokens        : how many tokens contributed (heroes + allies)
--  averageVictories : the averaged Victories used for the bonus
--  minLevel/maxLevel: the level range across the tokens
function Encounter.PartyStrengthFromTokens(tokens)
    local base = 0
    local numTokens = 0
    local totalVictories = 0
    local numHeroes = 0
    local minLevel = nil
    local maxLevel = nil
    for _, tok in ipairs(tokens or {}) do
        local level = tok.properties:CharacterLevel()
        if minLevel == nil or level < minLevel then
            minLevel = level
        end
        if maxLevel == nil or level > maxLevel then
            maxLevel = level
        end
        base = base + Encounter.HeroStrength(level)
        totalVictories = totalVictories + tok.properties:GetVictories()
        if tok.properties:IsHero() then
            numHeroes = numHeroes + 1
        end
        numTokens = numTokens + 1
    end

    if numTokens == 0 then
        return nil
    end

    local averageVictories = math.floor(totalVictories / numTokens)
    local singleHero = math.floor(base / numTokens)
    local victoryHeroes = math.floor(averageVictories / 2)
    local victoryBonus = math.floor(victoryHeroes * singleHero)
    return {
        total = base + victoryBonus,
        base = base,
        singleHero = singleHero,
        victoryBonus = victoryBonus,
        victoryHeroes = victoryHeroes,
        numHeroes = numHeroes,
        numTokens = numTokens,
        averageVictories = averageVictories,
        minLevel = minLevel,
        maxLevel = maxLevel,
    }
end

--Classify a monster EV total against a party strength table (from PartyStrength
--or PartyStrengthFromTokens). Returns one of Encounter.DifficultyTiers. With no
--party at all (nil strength) any roster is unwinnable, so it reads as Extreme.
function Encounter.DifficultyTier(ev, strength)
    if strength == nil or strength.total <= 0 then
        return "Extreme"
    end

    if ev < strength.total - strength.singleHero then
        return "Trivial"
    elseif ev < strength.total then
        return "Easy"
    elseif ev < strength.total + strength.singleHero then
        return "Standard"
    elseif ev <= strength.total + strength.singleHero * 3 then
        return "Hard"
    end
    return "Extreme"
end

--The EV boundaries between the difficulty tiers for a party strength table.
--Useful for drawing a budget meter. Returns:
--  trivialBelow  : EV below this is Trivial
--  easyBelow     : EV at/above trivialBelow but below this is Easy
--  standardBelow : EV at/above easyBelow but below this is Standard
--  hardMax       : EV at/above standardBelow up to and including this is Hard;
--                  anything above is Extreme
function Encounter.DifficultyBands(strength)
    return {
        trivialBelow = strength.total - strength.singleHero,
        easyBelow = strength.total,
        standardBelow = strength.total + strength.singleHero,
        hardMax = strength.total + strength.singleHero * 3,
    }
end

--Count the non-minion monsters across the WHOLE encounter (start groups + every
--reinforcement wave) at the given hero count. Uses CloneForNumberOfHeroes so the
--count reflects what actually spawns (minHeroes filtering + per-hero balancing).
--Minions are deliberately excluded. This is the total the victory checks measure
--against (e.g. the denominator for "Half Monsters Defeated").
-- Counts the non-minion monsters in the encounter for a given number of heroes
-- (including reinforcement waves). If org is given (a lowercase organization keyword
-- such as "leader"), only monsters of that organization are counted.
function Encounter.CountNonMinionMonsters(self, numHeroes, org)
    local clone = self:CloneForNumberOfHeroes(numHeroes)
    local count = 0
    for _, group in ipairs(clone.groups) do
        for monsterid, quantity in pairs(group.monsters) do
            local monster = assets.monsters[monsterid]
            if monster ~= nil and not monster.properties.minion and
                (org == nil or OrganizationKeyword(monster.properties) == org) then
                count = count + quantity
            end
        end
    end
    return count
end

function Encounter.Describe(self)
    --Build a lookup of waveid -> wave so we can annotate reinforcement monsters.
    local wavesById = {}
    for _, wave in ipairs(self:try_get("waves", {})) do
        wavesById[wave.id] = wave
    end

    --Aggregate start-of-encounter monsters together, and aggregate each wave's
    --monsters separately so reinforcements can carry their own italic annotation.
    local startMonsters = {}
    local waveMonsters = {}

    for i, group in ipairs(self.groups) do
        local waveid = group.wave
        local bucket
        if waveid ~= nil and wavesById[waveid] ~= nil then
            waveMonsters[waveid] = waveMonsters[waveid] or {}
            bucket = waveMonsters[waveid]
        else
            bucket = startMonsters
        end

        for monsterid, quantity in pairs(group.monsters) do
            bucket[monsterid] = (bucket[monsterid] or 0) + quantity
        end
    end

    local resultString = ""

    for monsterid, quantity in pairs(startMonsters) do
        local monster = assets.monsters[monsterid]
        resultString = resultString .. string.format("%d X %s \n", quantity, creature.GetTokenDescription(monster))
    end

    --Append reinforcement monsters, each tagged with a small italic note naming the
    --wave and the round it arrives on.
    for _, wave in ipairs(self:try_get("waves", {})) do
        local bucket = waveMonsters[wave.id]
        if bucket ~= nil then
            local note = string.format(" <size=80%%><i>(%s, %s)</i></size>", wave.name, Encounter.WaveRoundText(wave))
            for monsterid, quantity in pairs(bucket) do
                local monster = assets.monsters[monsterid]
                resultString = resultString .. string.format("%d X %s%s \n", quantity, creature.GetTokenDescription(monster), note)
            end
        end
    end

    return resultString
end

-- After an encounter's monsters are placed via the engine "click to place" path
-- (DocumentSystem/RichEncounter.lua's spawnFromBestiary handler, i.e. focus the
-- encounter in the journal then click the map), the spawned tokens -- INCLUDING the
-- reinforcement (wave) groups -- are plain and untagged. Tag the wave-group tokens
-- here with the same encounterWaveId / encounterGroupIndex / encounterSpawnSlot that
-- LiveEncounter:DeployWave applies, so RichEncounter's "Save and Remove" recognises
-- them and banks their positions into the wave groups.
--
-- charids must be in the engine's spawn order. That order matches a walk over the
-- groups in array order with per-hero-count adjusted quantities -- the SAME walk
-- RichEncounter's despawn uses for the start groups (which is why start positions
-- already round-trip). We advance the index across every group so the wave tokens
-- (which the engine spawns in their natural group position, last in the common case)
-- land on the right charids; we only tag the wave-group ones.
function Encounter.TagWaveTokensFromSpawn(self, charids)
    local numHeroes = dmhub.GetSettingValue("numheroes")
    local index = 1
    for gidx,group in ipairs(self.groups) do
        if group.minHeroes == nil or numHeroes >= group.minHeroes then
            local slot = 1
            for monsterid,quantity in pairs(group.monsters) do
                quantity = Encounter.AdjustedMonsterQuantity(group, monsterid, quantity, numHeroes)
                for i=1,quantity do
                    local charid = charids[index]
                    index = index + 1
                    if group.wave ~= nil and charid ~= nil then
                        local token = dmhub.GetTokenById(charid)
                        if token ~= nil then
                            token.properties.encounterWaveId = group.wave
                            token.properties.encounterGroupIndex = gidx
                            token.properties.encounterSpawnSlot = slot
                            token:UploadToken()
                        end
                    end
                    slot = slot + 1
                end
            end
        end
    end
end

-- LiveEncounter represents the state of an encounter that is currently running
-- (i.e. that has been pushed live into an initiative queue). It derives from
-- Encounter and begins life as a deep copy of an authored Encounter, re-typed as a
-- LiveEncounter so it is its own distinct type -- it inherits all of Encounter's
-- fields and methods but can carry live-only state and extensions.
LiveEncounter = RegisterGameType("LiveEncounter", "Encounter")

-- Its own table name so it is distinguished from authored encounters.
LiveEncounter.tableName = "liveencounters"

-- The non-minion monster count captured at the onset of combat (start groups + all
-- reinforcement waves). Used as the denominator for the "Half Monsters Defeated"
-- victory check so it stays stable as monsters die / reinforcements arrive.
LiveEncounter.onsetMonsterCount = 0

-- For the "Destroy the Thing!" victory condition: the number of Targetable objects on
-- the map matching the chosen keyword, captured at the onset of combat. Used so victory
-- is only ever declared if there was at least one "thing" to destroy to begin with, and
-- as the denominator/boss-bar trigger for the objective. See CheckVictory / GetBossToken.
LiveEncounter.onsetDestroyObjectCount = 0

-- Whether the objective progress is visible to players too. Defaults to false (only
-- the director sees it); the director can reveal it via the objective's eye icon.
LiveEncounter.objectiveVisible = false

-- Whether the boss bar (the Solo creature's Stamina bar shown below the combat tracker)
-- is visible to players too. Defaults to false (only the director sees it); the director
-- can reveal it via the boss bar's eye icon. See LiveEncounter:GetBossToken.
LiveEncounter.bossBarVisible = false

-- Set true when the director presses "Award Victory". This rides along inside the
-- networked initiative queue, so once it flips every client switches into the victory
-- state: the initiative bar is hidden and the full-screen victory screen
-- (Draw Steel UI/DSVictoryScreen.lua) is shown. Cleared when combat ends.
LiveEncounter.victoryAwarded = false

-- Set true when the director presses "Award" on the victory screen to grant each hero
-- this encounter's Victories. Networked (rides in the queue) so every client plays the
-- victory-icon drop animation and shows each hero's "Victories: old -> new" change.
LiveEncounter.victoriesAwarded = false

-- A snapshot of the heroes present at the onset of combat, used by the victory screen.
-- A list of { charid, name, recoveries }, where recoveries is how many Recoveries the
-- hero had available when combat began. Populated by RecordOnsetHeroes. Stored as a
-- dense list (not a sparse map) so it survives network serialization unchanged.
LiveEncounter.onsetHeroes = nil

-- Construct a LiveEncounter from an authored Encounter. The result is a deep copy
-- of the encounter's data, re-typed as a LiveEncounter: its typeName, metatable,
-- and tableName are updated to LiveEncounter so it serializes and behaves as a
-- LiveEncounter (while still inheriting everything from Encounter).
function LiveEncounter.Create(encounter)
    local result = DeepCopy(encounter)
    result.typeName = "LiveEncounter"
    result.tableName = LiveEncounter.tableName
    setmetatable(result, LiveEncounter.mt)
    --record the full non-minion monster count (including reinforcements that will
    --arrive) at the onset of combat.
    result.onsetMonsterCount = result:CountNonMinionMonsters()
    --for "Destroy the Thing!", record how many matching Targetable objects are on the
    --map at the onset of combat (the denominator / boss-bar trigger for that objective).
    if result:try_get("victoryCondition") == "destroy_thing" then
        local total = result:CountDestroyObjects()
        result.onsetDestroyObjectCount = total
    end
    --for "Leader Defeated", record how many Leader monsters (start groups + reinforcements)
    --the encounter contains at onset; victory is declared once all of them are defeated, so
    --this guards an encounter that never actually had a leader from being won instantly.
    if result:try_get("victoryCondition") == "leader_defeated" then
        result.onsetLeaderCount = result:CountNonMinionMonsters(nil, "leader")
    end
    --per-hero statistics for this encounter (see LiveEncounter:IncrementStat).
    --keyed by hero tokenid; sub-tables are vivified on first increment.
    result.stats = {}
    return result
end

-- A basic live encounter with no authored content: Encounter defaults (1
-- Victory reward, "all monsters defeated" victory condition), empty stats.
-- Every new initiative queue is created carrying one of these (see
-- InitiativeQueue.Create), so combat systems -- custom buttons, stat tracking,
-- victory awarding -- can rely on queue.liveEncounter being a LiveEncounter
-- even when combat was started without an authored encounter. Note
-- onsetMonsterCount comes out 0 (there are no authored monsters); callers that
-- know the real starting roster should seed it, as the Custom branch of the
-- "Draw Steel!" flow does (DSInitiativeRoll.lua).
function LiveEncounter.CreateEmpty()
    return LiveEncounter.Create(Encounter.new())
end

-- Returns the current number of Recoveries available to a hero (max minus those spent
-- on a long rest), and their maximum. Used both to snapshot the onset state and to read
-- the live state for the victory screen's "Recoveries: onset -> current/max" display.
local function HeroRecoveryCounts(props)
    if props == nil then
        return 0, 0
    end
    local recoveryId = CharacterResource.recoveryResourceId
    local max = props:GetResources()[recoveryId] or 0
    local used = props:GetResourceUsage(recoveryId, "long") or 0
    return max - used, max
end

-- Snapshot the heroes present at the onset of combat: their charid, display name, and
-- how many Recoveries they currently have. The victory screen reads this list so it can
-- show each hero and how their Recoveries changed over the fight. heroCharids is a set
-- (charid -> truthy), e.g. the player tokens gathered when initiative is rolled. Callers
-- must network the change afterwards (the live encounter rides inside the queue).
function LiveEncounter:RecordOnsetHeroes(heroCharids)
    local heroes = {}
    for charid, _ in pairs(heroCharids or {}) do
        local token = dmhub.GetTokenById(charid)
        if token ~= nil and token.properties ~= nil and token.properties:IsHero() then
            local current = HeroRecoveryCounts(token.properties)
            heroes[#heroes + 1] = {
                charid = charid,
                name = token.name,
                recoveries = current,
            }
        end
    end
    self.onsetHeroes = heroes
end

-- The onset hero snapshot (see RecordOnsetHeroes); always a list.
function LiveEncounter:GetOnsetHeroes()
    return self:try_get("onsetHeroes") or {}
end

-- The hero tokens currently in the battle (every IsHero entry in the initiative queue,
-- deduped, including the dead -- fallen heroes stay in initiative). This is what the
-- victory screen displays, so heroes appear as long as combat is live, independent of
-- whether the onset snapshot was captured. Returns a list of tokens.
function LiveEncounter:GetBattleHeroTokens()
    local q = dmhub.initiativeQueue
    local result = {}
    if q == nil then
        return result
    end
    local seen = {}
    for initiativeid, _ in pairs(q.entries) do
        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        for _, token in ipairs(tokens or {}) do
            if token ~= nil and not seen[token.charid] then
                local props = token.properties
                if props ~= nil and props:IsHero() then
                    seen[token.charid] = true
                    result[#result + 1] = token
                end
            end
        end
    end
    return result
end

-- For a hero token, return onset / current / max Recoveries. onset is nil when this hero
-- was not captured at the onset of combat (e.g. joined mid-fight).
function LiveEncounter:GetHeroRecoveries(token)
    local current, max = HeroRecoveryCounts(token and token.properties)
    local onset = nil
    for _, h in ipairs(self:GetOnsetHeroes()) do
        if h.charid == token.charid then
            onset = h.recoveries
            break
        end
    end
    return onset, current, max
end

-- The per-hero statistics table for this encounter, keyed by hero tokenid. Each
-- hero's sub-table is keyed by round ("round1", "round2", ...), and each round
-- bucket maps a statid to a running total for that round (see IncrementStat).
-- Always a table -- empty until the first stat is recorded. Read-only: mutate
-- through IncrementStat so the change is networked atomically.
function LiveEncounter:GetStats()
    return self:try_get("stats") or {}
end

--Recursively accumulate the numeric leaves of src into dest, preserving nested
--stat sub-tables (e.g. conditionsInflicted/<name>, tierRolls/<tier>).
local function SumStatsTables(dest, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            local d = dest[k]
            if type(d) ~= "table" then
                d = {}
                dest[k] = d
            end
            SumStatsTables(d, v)
        elseif type(v) == "number" then
            dest[k] = (type(dest[k]) == "number" and dest[k] or 0) + v
        end
    end
end

-- The whole-combat statistics for a single hero token (a map of statid -> total,
-- summed across all round buckets), or an empty table if none have been recorded
-- for that hero yet. Use GetStatsForTokenByRound for the per-round breakdown.
-- Returns a freshly-built table: safe for callers to keep, never a live view.
function LiveEncounter:GetStatsForToken(tokenid)
    local result = {}
    for _, roundStats in pairs(self:GetStats()[tokenid] or {}) do
        --non-table entries would be stats recorded before per-round bucketing;
        --they have no round to belong to and are skipped.
        if type(roundStats) == "table" then
            SumStatsTables(result, roundStats)
        end
    end
    return result
end

-- The per-round statistics recorded for a single hero token: a map of
-- "round<N>" -> { statid = total }, or an empty table. Read-only view.
function LiveEncounter:GetStatsForTokenByRound(tokenid)
    return self:GetStats()[tokenid] or {}
end

-- The statistics a single hero recorded in one specific round (a map of
-- statid -> total), or an empty table. `round` is the numeric round number.
function LiveEncounter:GetStatsForTokenInRound(tokenid, round)
    return self:GetStatsForTokenByRound(tokenid)[string.format("round%d", round)] or {}
end

-- Resolve the hero a stat should be attributed to. `tokenid` is the token that
-- triggered the stat (e.g. the token that landed a kill or dealt damage).
--
-- Summoned creatures (an animal companion, a minion summoned by a character, etc.)
-- attribute their stats to the hero that summoned them, so we walk the summon chain
-- (token.summonerid, which holds the summoner's tokenid) up to its root. Retainers
-- and followers are not summons -- they have no summonerid -- so when the summon
-- link runs out we follow their mentor relationship (IsRetainer/GetMentor) to the
-- hero instead; without this hop their stats would be silently dropped. The result
-- is only accepted if it is a hero (type "character") that is an active combatant in
-- the current encounter -- anything else (a monster, a monster's summon, or a hero
-- not in this combat) is rejected and the caller drops the stat. Returns the hero
-- token, or nil.
function LiveEncounter:ResolveStatHero(tokenid)
    if tokenid == nil then
        return nil
    end

    local token = dmhub.GetTokenById(tokenid)

    --walk up the summon chain (falling back to retainer mentor links) to the
    --root owner. Guard against cycles with a visited set and against runaway
    --chains with a hard cap.
    local seen = {}
    local guard = 0
    while token ~= nil and token.valid and not seen[token.charid] and guard < 16 do
        seen[token.charid] = true
        guard = guard + 1

        local nextToken = nil
        if token.summonerid and token.summonerid ~= "" then
            nextToken = dmhub.GetTokenById(token.summonerid)
        end

        if nextToken == nil then
            local props = token.properties
            if props ~= nil and props.IsRetainer ~= nil and props:IsRetainer() and props.GetMentor ~= nil then
                local mentor = props:GetMentor()
                if mentor ~= nil then
                    nextToken = dmhub.LookupToken(mentor)
                end
            end
        end

        if nextToken == nil or not nextToken.valid then
            break
        end
        token = nextToken
    end

    if token == nil or not token.valid or token.properties == nil or not token.properties:IsHero() then
        return nil
    end

    --must be a hero taking part in the current combat. GetBattleHeroTokens already
    --filters to IsHero entries in the live initiative queue, so membership here
    --confirms both "is a hero" and "is in this encounter".
    for _, heroToken in ipairs(self:GetBattleHeroTokens()) do
        if heroToken.charid == token.charid then
            return token
        end
    end

    return nil
end

-- Increment a per-hero statistic for this encounter. `tokenid` is the token that
-- triggered the stat; `statid` is the stat name, which may be a nested path using
-- "/" (e.g. "kills", or "monsterDamage/<monsterid>" to record damage dealt to a
-- specific monster -- the "monsterDamage" sub-table is created automatically by the
-- backend). `quantity` defaults to 1.
--
-- Examples:
--   encounter:IncrementStat(token.charid, "kills")                       -- +1 kill
--   encounter:IncrementStat(token.charid, "monsterDamage/"..monsterid, 8) -- +8 damage
--
-- The stat is only recorded for a valid hero (type "character") in the current
-- combat; summons of a hero attribute to their summoner, and any other token is
-- ignored (see ResolveStatHero). The actual add is routed through the server's
-- atomic increment (dmhub:IncrementInitiativeData), so concurrent writers from
-- multiple clients can't lose updates, and the resolved value rides back through
-- the normal initiative-queue broadcast.
function LiveEncounter:IncrementStat(tokenid, statid, quantity)
    if statid == nil or statid == "" then
        return
    end

    if quantity == nil then
        quantity = 1
    end

    local heroToken = self:ResolveStatHero(tokenid)
    if heroToken == nil then
        return
    end

    --bucket the stat by combat round (stats/<tokenid>/round<N>/<statid>) so all
    --stats are recorded per round; whole-combat totals are produced by summing
    --the round buckets on read (see GetStatsForToken). "roundN" string keys
    --rather than bare numbers so no serialization layer mistakes the sub-table
    --for an array.
    local round = 0
    local q = dmhub.initiativeQueue
    if q ~= nil then
        round = q.round or 0
    end

    --path relative to the initiative queue root; the live encounter rides inside
    --the queue at liveEncounter, with per-hero stats under stats/<tokenid>.
    local path = string.format("liveEncounter/stats/%s/round%d/%s", heroToken.charid, round, statid)
    dmhub:IncrementInitiativeData(path, quantity)
end

-- Convenience entry point for recording a hero stat from anywhere in the codebase
-- without the caller having to find the live encounter or guard any edge cases.
--
--   LiveEncounter.TrackHeroStats(token.charid, "kills")
--
-- "just works": it locates the current combat's live encounter and records the stat,
-- or quietly does nothing if any precondition is not met --
--   (1) the token resolves to a hero (a summon is followed up to its summoner), and
--   (2) we are in combat with a LiveEncounter in which that hero is participating.
-- Only when both hold is the stat accumulated (atomically, server-side).
--
-- This is the safe, static public surface: it is wrapped so it never throws, making
-- it safe to drop directly into hot combat / damage code paths. The actual validation
-- (hero check, summon attribution, combat-participation check) and the networked
-- accumulation live in IncrementStat / ResolveStatHero.
--
-- tokenid: the token that triggered the stat. statid: the stat name, optionally a
-- "/"-separated nested path (e.g. "monsterDamage/<monsterid>"). quantity: default 1.
function LiveEncounter.TrackHeroStats(tokenid, statid, quantity)
    local ok, err = pcall(function()
        if tokenid == nil or statid == nil or statid == "" then
            return
        end

        --must be in active combat (initiative present and not hidden).
        local q = dmhub.initiativeQueue
        if q == nil or q:try_get("hidden") then
            return
        end

        --a LiveEncounter must be live in this combat (the field can be false, nil,
        --or a table -- only a table is a real live encounter).
        local live = q:try_get("liveEncounter")
        if type(live) ~= "table" then
            return
        end

        --delegate: IncrementStat does the hero/summoner/participation validation and
        --drops the stat itself if the token is not a participating hero.
        live:IncrementStat(tokenid, statid, quantity)
    end)

    if not ok then
        dmhub.Debug(string.format("LiveEncounter.TrackHeroStats: failed to record stat '%s': %s", tostring(statid), tostring(err)))
    end
end

-- The display name of the live encounter (the live encounter is itself a copy of
-- the authored encounter, so this is just its name).
function LiveEncounter:GetName()
    return self:try_get("name")
end

-- The "readied" encounter: an Encounter the DM has staged via an encounter's
-- "Place on Map" button (see DocumentSystem/RichEncounter.lua). It is transient
-- (in-memory only, not serialized): it is consulted to pre-select that encounter in
-- the combat-setup dropdown, and cleared once combat actually starts.
local g_readiedEncounter = nil

function Encounter.SetReadiedEncounter(encounter)
    g_readiedEncounter = encounter
end

function Encounter.GetReadiedEncounter()
    return g_readiedEncounter
end

function Encounter.ClearReadiedEncounter()
    g_readiedEncounter = nil
end

-- Set of wave ids that have already been deployed (or dismissed) during this live
-- encounter. A deployed wave's reinforcement button no longer shows. Empty by
-- default; mutated through MarkWaveDeployed (which copies-on-write so the shared
-- default is never touched).
LiveEncounter.deployedWaves = {}

-- True if the given wave has already been deployed/dismissed.
function LiveEncounter:IsWaveDeployed(waveid)
    local deployed = self:try_get("deployedWaves")
    return deployed ~= nil and deployed[waveid] == true
end

-- Mark a wave as deployed/dismissed so its reinforcement button stops showing.
-- Callers must network the change (e.g. info.UploadInitiative()) afterwards, since
-- the live encounter rides along inside the initiative queue.
function LiveEncounter:MarkWaveDeployed(waveid)
    self.deployedWaves = DeepCopy(self:try_get("deployedWaves", {}))
    self.deployedWaves[waveid] = true
end

-- Does the given wave have at least one group with at least one monster?
function LiveEncounter:WaveHasMonsters(waveid)
    for _, group in ipairs(self.groups) do
        if group.wave == waveid then
            for _ in pairs(group.monsters) do
                return true
            end
        end
    end
    return false
end

-- Returns the list of waves that are currently available to deploy: not already
-- deployed, holding at least one monster, and whose arrival round has been reached
-- (a numeric round arrives when currentRound >= that round; "every" is available on
-- any round).
function LiveEncounter:GetAvailableWaves(currentRound)
    local result = {}
    for _, wave in ipairs(self:try_get("waves", {})) do
        if not self:IsWaveDeployed(wave.id) and self:WaveHasMonsters(wave.id) then
            local arrived = (wave.round == "every") or (type(wave.round) == "number" and currentRound >= wave.round)
            if arrived then
                result[#result + 1] = wave
            end
        end
    end
    return result
end

-- Set of cue ids that have already been fired (or dismissed) during this live
-- encounter. A fired cue's banner no longer shows. Mirrors deployedWaves,
-- including the copy-on-write so the shared default is never touched.
LiveEncounter.firedCues = {}

-- True if the given cue has already been fired/dismissed.
function LiveEncounter:IsCueFired(cueid)
    local fired = self:try_get("firedCues")
    return fired ~= nil and fired[cueid] == true
end

-- Mark a cue as fired/dismissed so its banner stops showing. Callers must
-- network the change (e.g. info.UploadInitiative()) afterwards, since the live
-- encounter rides along inside the initiative queue.
function LiveEncounter:MarkCueFired(cueid)
    self.firedCues = DeepCopy(self:try_get("firedCues", {}))
    self.firedCues[cueid] = true
end

-- Returns the list of cues whose banner should currently show: not already
-- fired, and whose round has been reached (numeric round arrives when
-- currentRound >= that round; "every" is available on any round).
function LiveEncounter:GetAvailableCues(currentRound)
    local result = {}
    for _, cue in ipairs(self:try_get("cues", {})) do
        if not self:IsCueFired(cue.id) then
            local arrived = (cue.round == "every") or (type(cue.round) == "number" and currentRound >= cue.round)
            if arrived then
                result[#result + 1] = cue
            end
        end
    end
    return result
end

-- Custom buttons: script-driven action buttons surfaced to the Director on the
-- initiative bar (the Encounter Actions strip in MCDMInitiativeBar.lua). Unlike
-- waves and cues these are not authored into the encounter: runtime code (map
-- object scripts, macros, etc.) adds and removes them on the live encounter
-- while combat runs. Each button is a plain table of scalars:
--   id      : required stable string identifying the button.
--   name    : title shown on the button.
--   summary : optional subtitle shown under the title.
--   tooltip : optional hover text; defaults to the name.
--   command : chat-style command line (no leading slash, e.g.
--             "gnollarmy summon") executed via dmhub.Execute on the
--             Director's client when the button is clicked.
--   sticky  : optional; by default a button removes itself when clicked so a
--             slow interactive command cannot be double-fired. Set true to
--             keep the button until code removes it.
--   malice  : optional malice cost (number). The strip renders the cost in a
--             malice diamond on the button, hides the button entirely while
--             the Director has less malice than the cost, and spends the
--             malice on click (before running the command).
-- Buttons ride inside the networked initiative queue like all other live
-- encounter state, so mutations must be followed by an upload
-- (info.UploadInitiative() / dmhub:UploadInitiativeQueue()). The static
-- Ensure/Dismiss helpers below handle the lookup and upload for callers.
LiveEncounter.customButtons = {}

-- Shallow comparison of two custom-button tables (buttons are flat tables of
-- scalars, so a shallow compare is exact).
local function CustomButtonsEqual(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then
            return false
        end
    end
    for k, v in pairs(b) do
        if a[k] ~= v then
            return false
        end
    end
    return true
end

-- The list of custom buttons currently on this live encounter (empty if none).
function LiveEncounter:GetCustomButtons()
    return self:try_get("customButtons", {})
end

-- Find a custom button by id, or nil.
function LiveEncounter:GetCustomButton(buttonid)
    for _, button in ipairs(self:try_get("customButtons", {})) do
        if button.id == buttonid then
            return button
        end
    end
    return nil
end

-- Add or update (by id) a custom button. Copy-on-write so the shared type
-- default is never mutated. Returns true if anything actually changed; callers
-- must network the change afterwards.
function LiveEncounter:SetCustomButton(button)
    if type(button) ~= "table" or button.id == nil then
        return false
    end

    local existing = self:GetCustomButton(button.id)
    if existing ~= nil and CustomButtonsEqual(existing, button) then
        return false
    end

    local buttons = DeepCopy(self:try_get("customButtons", {}))
    local replaced = false
    for i, b in ipairs(buttons) do
        if b.id == button.id then
            buttons[i] = DeepCopy(button)
            replaced = true
            break
        end
    end
    if not replaced then
        buttons[#buttons + 1] = DeepCopy(button)
    end
    self.customButtons = buttons
    return true
end

-- Remove a custom button by id. Returns true if it was present. Callers must
-- network the change afterwards.
function LiveEncounter:RemoveCustomButton(buttonid)
    local buttons = self:try_get("customButtons")
    if buttons == nil then
        return false
    end
    local result = {}
    local removed = false
    for _, button in ipairs(buttons) do
        if button.id == buttonid then
            removed = true
        else
            result[#result + 1] = button
        end
    end
    if removed then
        self.customButtons = result
    end
    return removed
end

-- Safe static entry point for scripts: upsert the button on the current live
-- encounter and network the change. Does nothing (cleanly) when there is no
-- active combat or the combat has no live encounter (combat started Custom).
-- Call on the Director's client. Returns true if the button was added/updated.
function LiveEncounter.EnsureCustomButton(button)
    local result = false
    pcall(function()
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            return
        end
        local liveEncounter = q:try_get("liveEncounter")
        if type(liveEncounter) ~= "table" then
            return
        end
        if liveEncounter:SetCustomButton(button) then
            dmhub:UploadInitiativeQueue()
            result = true
        end
    end)
    return result
end

-- Safe static counterpart to EnsureCustomButton: remove the button from the
-- current live encounter and network the change. Returns true if it was there.
function LiveEncounter.DismissCustomButton(buttonid)
    local result = false
    pcall(function()
        local q = dmhub.initiativeQueue
        if q == nil then
            return
        end
        local liveEncounter = q:try_get("liveEncounter")
        if type(liveEncounter) ~= "table" then
            return
        end
        if liveEncounter:RemoveCustomButton(buttonid) then
            dmhub:UploadInitiativeQueue()
            result = true
        end
    end)
    return result
end

-- Deploy a wave: spawn the monsters of every group assigned to the wave, add each
-- group to the initiative queue, and mark the wave deployed. Reinforcement groups
-- are not pre-positioned (see RichEncounter spawn, which skips wave groups), so when
-- a group has no authored spawn locations the monsters are spread in a small grid
-- around the camera centre for the DM to reposition. Returns the number of tokens
-- spawned.
function LiveEncounter:DeployWave(waveid, initiativeQueue)
    local cam = dmhub.cameraPosition
    local baseX = round(cam.x)
    local baseY = round(cam.y)
    local floorIndex = game.currentFloorIndex

    local numHeroes = dmhub.GetSettingValue("numheroes")
    local spawnedCount = 0
    local fallbackIndex = 0

    for groupIndex, group in ipairs(self.groups) do
        if group.wave == waveid then
            --determine minion squad naming, mirroring RichEncounter.spawn.
            local minionName = nil
            local nsquads = 1
            for monsterid, quantity in pairs(group.monsters) do
                local monsterAsset = assets.monsters[monsterid]
                if monsterAsset ~= nil and monsterAsset.properties:IsMonster() and monsterAsset.properties.minion then
                    minionName = monsterAsset.properties.monster_type
                    if quantity >= 8 then
                        nsquads = math.ceil(quantity / (group.squadSize or 4))
                    end
                    break
                end
            end

            local squadNames = nil
            if minionName ~= nil then
                squadNames = {}
                for i = 1, nsquads do
                    --FindFreshSquadName is a static function on the global monster game type.
                    squadNames[#squadNames + 1] = monster.FindFreshSquadName(minionName)
                end
            end

            local groupid = dmhub.GenerateGuid()
            local spawnIndex = 1
            local nsquad = 1
            local spawnedInGroup = false

            for monsterid, quantity in pairs(group.monsters) do
                for i = 1, quantity do
                    --the slot this token occupies in the group's flat spawn order; used
                    --to read its saved location and to tag it for "Save and Remove".
                    local slot = spawnIndex
                    --prefer an authored spawn location if one exists; otherwise lay the
                    --monsters out in a 5-wide grid around the camera centre.
                    local loc = (group.spawnlocs or {})[slot]
                    if loc ~= nil then
                        if not loc.isValidFloor then
                            loc = loc.withCurrentFloor
                        end
                    else
                        local col = fallbackIndex % 5
                        local row = math.floor(fallbackIndex / 5)
                        loc = core.Loc { x = baseX + col, y = baseY + row, floorIndex = floorIndex }
                    end
                    spawnIndex = spawnIndex + 1
                    fallbackIndex = fallbackIndex + 1

                    local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true })
                    if token ~= nil then
                        token.properties.initiativeGrouping = groupid
                        token.properties:OnCreateFromBestiary(token, groupid)
                        token.properties.minHeroes = (group.monsterMinHeroes or {})[monsterid] or group.minHeroes

                        --Tag the token so RichEncounter's "Save and Remove" can find it
                        --on the map and bank its position back into the authored
                        --encounter's wave group -- independent of whether combat is
                        --still active or which live encounter is current. groupIndex is
                        --stable because the live encounter is a plain deep copy of the
                        --authored encounter (groups are never reordered), and slot maps
                        --to the same flat spawn order DeployWave reads above.
                        token.properties.encounterWaveId = waveid
                        token.properties.encounterGroupIndex = groupIndex
                        token.properties.encounterSpawnSlot = slot

                        --restore saved appearance / invisibility for this slot, if any.
                        local appearanceInfo = (group.appearances or {})[slot]
                        if type(appearanceInfo) == "string" then
                            token:SerializeAppearanceFromString(appearanceInfo)
                        end
                        if (group.invisibleToPlayers or {})[slot] then
                            token.invisibleToPlayers = true
                        end

                        local balancing = group.balancing
                        if balancing ~= nil then
                            local info = balancing[numHeroes]
                            if info ~= nil and type(info.stamina) == "number" then
                                token.properties.max_hitpoints = info.stamina
                            end
                        end

                        if squadNames ~= nil then
                            token.properties.minionSquad = squadNames[nsquad]
                            nsquad = nsquad + 1
                            if nsquad > #squadNames then
                                nsquad = 1
                            end
                        end

                        token:UploadToken()
                        game.UpdateCharacterTokens()

                        spawnedCount = spawnedCount + 1
                        spawnedInGroup = true
                    end
                end
            end

            --register the freshly spawned group with the active initiative queue so
            --the reinforcements take their turn this combat.
            if spawnedInGroup and initiativeQueue ~= nil then
                initiativeQueue:SetInitiative(groupid, 0, 0)
            end
        end
    end

    self:MarkWaveDeployed(waveid)
    return spawnedCount
end

-- Count the non-minion reinforcement monsters that have NOT yet been deployed (their
-- wave is not in deployedWaves). These are monsters that "will arrive" -- they count
-- toward the monsters the heroes still have to deal with even though they're not yet
-- on the map.
-- If org is given (a lowercase organization keyword such as "leader"), only pending
-- reinforcement monsters of that organization are counted.
function LiveEncounter:CountPendingReinforcements(numHeroes, org)
    numHeroes = numHeroes or dmhub.GetSettingValue("numheroes")
    local clone = self:CloneForNumberOfHeroes(numHeroes)
    local count = 0
    for _, group in ipairs(clone.groups) do
        if group.wave ~= nil and not self:IsWaveDeployed(group.wave) then
            for monsterid, quantity in pairs(group.monsters) do
                local monster = assets.monsters[monsterid]
                if monster ~= nil and not monster.properties.minion and
                    (org == nil or OrganizationKeyword(monster.properties) == org) then
                    count = count + quantity
                end
            end
        end
    end
    return count
end

-- Walk the active initiative queue and count the live combatants on each side:
--   heroes  : hero/player tokens with Stamina (hitpoints) > 0
--   monsters: non-minion monster tokens with Stamina > 0 (minions are ignored)
-- Returns heroes, monsters. A combatant counts as "live"/standing while its current
-- Stamina is above 0.
function LiveEncounter:CountLiveCombatants()
    local q = dmhub.initiativeQueue
    local heroes, monsters = 0, 0
    if q == nil then
        return heroes, monsters
    end

    local seen = {}
    for initiativeid, _ in pairs(q.entries) do
        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        for _, token in ipairs(tokens or {}) do
            if token ~= nil and not seen[token.charid] then
                seen[token.charid] = true
                local props = token.properties
                if props ~= nil and props:CurrentHitpoints() > 0 then
                    if props:IsHero() then
                        heroes = heroes + 1
                    elseif props:IsMonster() and not props.minion then
                        monsters = monsters + 1
                    end
                end
            end
        end
    end

    return heroes, monsters
end

-- "Solo Exhausted": there is a Solo monster in the encounter that has used ALL of its
-- villain actions AND is at a quarter or less of its maximum Stamina. A monster's
-- villain actions are its activated abilities carrying a non-empty villainAction key
-- (slot); each slot is consumed once per encounter (tracked by VillainActionState).
function LiveEncounter:IsSoloExhausted()
    local q = dmhub.initiativeQueue
    if q == nil then
        return false
    end

    local seen = {}
    for initiativeid, _ in pairs(q.entries) do
        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        for _, token in ipairs(tokens or {}) do
            if token ~= nil and not seen[token.charid] then
                seen[token.charid] = true
                local props = token.properties
                if props ~= nil and props:IsMonster() and props:try_get("role") == "Solo" then
                    --gather this solo's villain action slots.
                    local vaSlots = {}
                    local abilities = props:GetActivatedAbilities()
                    if abilities ~= nil then
                        for _, ab in ipairs(abilities) do
                            local key = ab:try_get("villainAction")
                            if key ~= nil and key ~= "" then
                                vaSlots[#vaSlots + 1] = key
                            end
                        end
                    end

                    --it must actually have villain actions, and all must be used.
                    local allUsed = #vaSlots > 0
                    for _, slot in ipairs(vaSlots) do
                        if not VillainActionState.HasUsed(token.charid, slot) then
                            allUsed = false
                            break
                        end
                    end

                    local maxhp = props:MaxHitpoints()
                    local lowStamina = maxhp > 0 and props:CurrentHitpoints() <= maxhp / 4

                    if allUsed and lowStamina then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- For "Destroy the Thing!": counts the Targetable objects on the map matching the chosen
-- keyword, returning (total, live) where:
--   total : how many matching objects are currently on the map (destroyed or not)
--   live  : how many of those still have Stamina above 0
-- An object that has been removed from the map is gone and counts toward neither.
function LiveEncounter:CountDestroyObjects()
    local keyword = self:try_get("victoryDestroyKeyword")
    local tokens = Encounter.GetTargetableObjectsWithKeyword(keyword)
    local total, live = 0, 0
    for _, token in ipairs(tokens) do
        total = total + 1
        local props = token.properties
        if props ~= nil and props:CurrentHitpoints() > 0 then
            live = live + 1
        end
    end
    return total, live
end

-- Returns the first non-minion monster token in the active initiative queue whose
-- organization matches the given lowercase keyword (e.g. "leader"), alive or defeated,
-- or nil if none is present. Used to locate the encounter's leader for the boss bar.
function LiveEncounter:GetFirstMonsterWithOrganization(org)
    local q = dmhub.initiativeQueue
    if q == nil then
        return nil
    end
    local seen = {}
    for initiativeid, _ in pairs(q.entries) do
        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        for _, token in ipairs(tokens or {}) do
            if token ~= nil and not seen[token.charid] then
                seen[token.charid] = true
                local props = token.properties
                if props ~= nil and props:IsMonster() and not props.minion and OrganizationKeyword(props) == org then
                    return token
                end
            end
        end
    end
    return nil
end

-- Counts the live (Stamina > 0) non-minion Leader monsters currently in the active
-- initiative queue. A defeated leader (0 Stamina) or one removed from the queue is not
-- counted, which is what drives the "Leader Defeated" victory check.
function LiveEncounter:CountLiveLeaders()
    local q = dmhub.initiativeQueue
    local count = 0
    if q == nil then
        return count
    end
    local seen = {}
    for initiativeid, _ in pairs(q.entries) do
        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        for _, token in ipairs(tokens or {}) do
            if token ~= nil and not seen[token.charid] then
                seen[token.charid] = true
                local props = token.properties
                if props ~= nil and props:IsMonster() and not props.minion and
                    OrganizationKeyword(props) == "leader" and props:CurrentHitpoints() > 0 then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Returns the creature's token to display in the boss bar, or nil if no boss bar
-- should be shown. A boss bar is appropriate when:
--   * the victory condition is "Solo Exhausted" (the objective is literally to wear the
--     solo down), or
--   * the victory condition is "all monsters defeated" AND the encounter contains exactly
--     one non-minion monster with the Solo role, or
--   * the victory condition is "Leader Defeated" AND the encounter contains a Leader (the
--     bar tracks that leader's Stamina), or
--   * the victory condition is "Destroy the Thing!" AND exactly one matching object was
--     present at the onset of combat (the bar then tracks that object's Stamina).
-- The bar tracks the chosen creature/object's Stamina. Minions are ignored.
function LiveEncounter:GetBossToken()
    --Script-set victory conditions have no boss-bar objective; the stored
    --victoryCondition underneath is stale while a script owns victory.
    if self:ScriptVictoryText() ~= nil then
        return nil
    end

    local condition = self:try_get("victoryCondition", "all_defeated")

    if condition == "destroy_thing" then
        --only surface a boss bar when the heroes must destroy a single "thing".
        if self:try_get("onsetDestroyObjectCount", 0) ~= 1 then
            return nil
        end
        local keyword = self:try_get("victoryDestroyKeyword")
        local tokens = Encounter.GetTargetableObjectsWithKeyword(keyword)
        return tokens[1]
    end

    if condition == "leader_defeated" then
        --track the encounter's leader; the first one present (alive or downed) drives the bar.
        return self:GetFirstMonsterWithOrganization("leader")
    end

    if condition ~= "solo_exhausted" and condition ~= "all_defeated" then
        return nil
    end

    local q = dmhub.initiativeQueue
    if q == nil then
        return nil
    end

    local solos = {}
    local seen = {}
    for initiativeid, _ in pairs(q.entries) do
        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        for _, token in ipairs(tokens or {}) do
            if token ~= nil and not seen[token.charid] then
                seen[token.charid] = true
                local props = token.properties
                if props ~= nil and props:IsMonster() and not props.minion and props:try_get("role") == "Solo" then
                    solos[#solos + 1] = token
                end
            end
        end
    end

    if condition == "solo_exhausted" then
        --the objective explicitly targets the solo; show the first one present.
        return solos[1]
    end

    --all_defeated: only surface a boss bar for a single-solo encounter.
    if #solos == 1 then
        return solos[1]
    end

    return nil
end

-- Returns true when this encounter's configured victory condition has been met.
-- Minions are never counted. "Monsters remaining" = live non-minion monsters on the
-- field PLUS reinforcements that have not yet arrived, so victory is not declared
-- while a wave is still pending. See Encounter.GetVictoryConditions for the ids.
function LiveEncounter:CheckVictory()
    --An attached encounter script with a custom victory condition replaces the
    --built-in conditions entirely (see the Encounter Scripts section below).
    --Evaluated under pcall; a broken script can never accidentally declare
    --victory.
    local scriptInstance, scriptDef = self:GetScriptVictory()
    if scriptDef ~= nil then
        return EncounterScript.EvaluateVictoryCheck(self, scriptInstance, scriptDef)
    end

    local condition = self:try_get("victoryCondition", "all_defeated")

    --"Destroy the Thing!" is about objects, not monsters, so it is checked before the
    --monster-onset guard. Victory once no live matching object remains (each is either
    --removed from the map or reduced to 0 Stamina), provided at least one existed.
    if condition == "destroy_thing" then
        if self:try_get("victoryDestroyKeyword") == nil then
            return false
        end
        if self:try_get("onsetDestroyObjectCount", 0) <= 0 then
            return false
        end
        local _, live = self:CountDestroyObjects()
        return live <= 0
    end

    --no monsters were ever part of this encounter -> nothing to win.
    local onset = self:try_get("onsetMonsterCount", 0)
    if onset <= 0 then
        return false
    end

    local numHeroes = dmhub.GetSettingValue("numheroes")
    local heroes, monstersOnField = self:CountLiveCombatants()
    local monstersRemaining = monstersOnField + self:CountPendingReinforcements(numHeroes)

    if condition == "all_defeated" then
        return monstersRemaining <= 0
    elseif condition == "heroes_outnumber" then
        return heroes > 0 and heroes > monstersRemaining
    elseif condition == "heroes_outnumber_two_to_one" then
        return heroes > 0 and heroes >= 2 * monstersRemaining
    elseif condition == "half_defeated" then
        local defeated = onset - monstersRemaining
        return defeated * 2 >= onset
    elseif condition == "solo_exhausted" then
        return self:IsSoloExhausted()
    elseif condition == "leader_defeated" then
        --victory once every Leader monster is defeated: none live on the field and none
        --still pending as a reinforcement. Guarded by the onset leader count so an
        --encounter that never actually contained a leader cannot be won instantly.
        if self:try_get("onsetLeaderCount", 0) <= 0 then
            return false
        end
        return self:CountLiveLeaders() + self:CountPendingReinforcements(numHeroes, "leader") <= 0
    end

    return false
end

-- Progress toward victory expressed purely as monster defeats: returns
--   defeated : how many non-minion monsters have been defeated so far
--   needed   : how many must be defeated for victory
-- For the count conditions this is direct; for the "outnumber" conditions we convert
-- the threshold into a number of kills (how many monsters must be removed so the
-- heroes reach the required ratio). Both numbers reference the onset total (start
-- groups + reinforcements that will arrive). "threshold" is how many monsters may
-- remain at victory.
function LiveEncounter:GetDefeatProgress()
    local condition = self:try_get("victoryCondition", "all_defeated")
    local onset = self:try_get("onsetMonsterCount", 0)
    local numHeroes = dmhub.GetSettingValue("numheroes")
    local heroes, monstersOnField = self:CountLiveCombatants()
    local monstersRemaining = monstersOnField + self:CountPendingReinforcements(numHeroes)

    local threshold = 0
    if condition == "half_defeated" then
        --need to defeat ceil(onset/2); that leaves floor(onset/2) standing.
        threshold = onset - math.ceil(onset / 2)
    elseif condition == "heroes_outnumber" then
        --win when monstersRemaining < heroes -> at most heroes-1 may remain.
        threshold = heroes - 1
    elseif condition == "heroes_outnumber_two_to_one" then
        --win when heroes >= 2*monstersRemaining -> at most floor(heroes/2) may remain.
        threshold = math.floor(heroes / 2)
    end
    --"all_defeated" leaves threshold at 0.

    if threshold < 0 then threshold = 0 end
    if threshold > onset then threshold = onset end

    local needed = onset - threshold
    if needed < 0 then needed = 0 end

    local defeated = onset - monstersRemaining
    if defeated < 0 then defeated = 0 end
    if defeated > needed then defeated = needed end

    return defeated, needed
end

-- A short progress description of the configured victory condition, suitable for an
-- "Objective" label shown while the encounter is in progress, e.g.
-- "Objective: Defeat 2/4 monsters to win" (2 = currently defeated, 4 = total needed).
-- Every condition is expressed this way for brevity (the full reasoning is in
-- GetObjectiveTooltip); "Solo Exhausted" is the one exception, as it is not a count.
function LiveEncounter:GetObjectiveText()
    --A script-set victory condition displays its cached text. The string is
    --resolved at edit time on the authoring director's client, so surfaces that
    --render on player clients never execute encounter-script code.
    local scriptText = self:ScriptVictoryText()
    if scriptText ~= nil then
        return "Objective: " .. scriptText
    end

    local condition = self:try_get("victoryCondition", "all_defeated")
    if condition == "solo_exhausted" then
        return "Objective: Exhaust the solo monster to win"
    elseif condition == "leader_defeated" then
        return "Objective: Defeat the leader to win"
    elseif condition == "destroy_thing" then
        local keyword = self:try_get("victoryDestroyKeyword", "thing")
        local onset = self:try_get("onsetDestroyObjectCount", 0)
        if onset <= 1 then
            return string.format("Objective: Destroy the %s to win", keyword)
        end
        local _, live = self:CountDestroyObjects()
        local destroyed = onset - live
        if destroyed < 0 then destroyed = 0 end
        if destroyed > onset then destroyed = onset end
        return string.format("Objective: Destroy %d/%d %s to win", destroyed, onset, keyword)
    end

    local defeated, needed = self:GetDefeatProgress()
    return string.format("Objective: Defeat %d/%d monsters to win", defeated, needed)
end

-- The full explanatory text for the objective, shown as a tooltip: states the actual
-- victory condition and the live numbers behind the short "Defeat X/Y" label.
function LiveEncounter:GetObjectiveTooltip()
    --Script-set victory conditions: cached text plus attribution.
    local scriptText, scriptInstance = self:ScriptVictoryText()
    if scriptText ~= nil then
        local scriptName = "Encounter Script"
        if scriptInstance ~= nil then
            scriptName = scriptInstance:try_get("name", scriptName)
        end
        return string.format("%s\n\nVictory condition set by the encounter script \"%s\".", scriptText, scriptName)
    end

    local condition = self:try_get("victoryCondition", "all_defeated")
    local onset = self:try_get("onsetMonsterCount", 0)
    local numHeroes = dmhub.GetSettingValue("numheroes")
    local heroes, monstersOnField = self:CountLiveCombatants()
    local pending = self:CountPendingReinforcements(numHeroes)

    local lines = {}
    if condition == "all_defeated" then
        lines[#lines + 1] = "Victory when every non-minion monster is defeated."
    elseif condition == "half_defeated" then
        lines[#lines + 1] = "Victory when at least half of the encounter's non-minion monsters are defeated."
    elseif condition == "heroes_outnumber" then
        lines[#lines + 1] = "Victory when the living heroes outnumber the remaining monsters, so the monsters lose their nerve and flee. The kill count shows how many monsters must fall to reach that point."
    elseif condition == "heroes_outnumber_two_to_one" then
        lines[#lines + 1] = "Victory when the living heroes outnumber the remaining monsters two-to-one, so the monsters lose their nerve and flee. The kill count shows how many monsters must fall to reach that point."
    elseif condition == "solo_exhausted" then
        return "Victory when the solo monster has spent all of its villain actions and is reduced to one quarter Stamina or less."
    elseif condition == "leader_defeated" then
        local liveLeaders = self:CountLiveLeaders()
        local pendingLeaders = self:CountPendingReinforcements(numHeroes, "leader")
        local tooltipLines = {
            "Victory when the encounter's Leader monster is defeated (reduced to 0 Stamina or removed from the field).",
            "",
            string.format("Leaders at onset: %d", self:try_get("onsetLeaderCount", 0)),
            string.format("Leaders still standing: %d", liveLeaders),
        }
        if pendingLeaders > 0 then
            tooltipLines[#tooltipLines + 1] = string.format("Leaders still to arrive: %d", pendingLeaders)
        end
        return table.concat(tooltipLines, "\n")
    elseif condition == "destroy_thing" then
        local keyword = self:try_get("victoryDestroyKeyword", "thing")
        local onsetObjects = self:try_get("onsetDestroyObjectCount", 0)
        local _, live = self:CountDestroyObjects()
        local destroyed = onsetObjects - live
        if destroyed < 0 then destroyed = 0 end
        local tooltipLines = {
            string.format("Victory when every object with the \"%s\" keyword has been destroyed (reduced to 0 Stamina) or removed from the map.", keyword),
            "",
            string.format("Things to destroy at onset: %d", onsetObjects),
            string.format("Still standing: %d", live),
            string.format("Destroyed or removed: %d", destroyed),
        }
        return table.concat(tooltipLines, "\n")
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("Total monsters (minions excluded): %d", onset)
    lines[#lines + 1] = string.format("Living on the field: %d", monstersOnField)
    if pending > 0 then
        lines[#lines + 1] = string.format("Reinforcements still to arrive: %d", pending)
    end
    lines[#lines + 1] = string.format("Living heroes: %d", heroes)

    local defeated, needed = self:GetDefeatProgress()
    lines[#lines + 1] = string.format("Defeated %d of the %d needed to win.", defeated, needed)

    return table.concat(lines, "\n")
end

-- Returns true when an attached encounter script's defeat condition has been
-- met. Defeat conditions only exist via scripts (there are no built-in ones),
-- so this is false for encounters without a defeat-declaring script. Evaluated
-- under pcall; a broken script can never accidentally end a fight in defeat.
function LiveEncounter:CheckDefeat()
    local instance, def = self:GetScriptDefeat()
    if def == nil then
        return false
    end
    return EncounterScript.EvaluateDefeatCheck(self, instance, def)
end

-- A short progress description of the script-set defeat condition for the
-- initiative bar's objective strip, e.g. "Defeat: 2/4 Monsters Have Entered
-- the Temple", or nil when no attached script declares a defeat condition.
function LiveEncounter:GetDefeatText()
    local text = self:ScriptDefeatText()
    if text == nil then
        return nil
    end
    return "Defeat: " .. text
end

-- The full explanatory tooltip for the defeat condition, or nil.
function LiveEncounter:GetDefeatTooltip()
    local text, instance = self:ScriptDefeatText()
    if text == nil then
        return nil
    end
    local scriptName = "Encounter Script"
    if instance ~= nil then
        scriptName = instance:try_get("name", scriptName)
    end
    return string.format("%s\n\nDefeat condition set by the encounter script \"%s\". If it is met, the director can declare defeat, which ends the encounter.", text, scriptName)
end

-- Scour the journals available on the current map for authored encounters.
--
-- Two sources are searched:
--   1. Info bubbles on the current map (dmhub.infoBubbles), each of which
--      references a journal (markdown) document.
--   2. Game-wide journal documents -- every markdown document in the journal
--      whose folder chain roots at an accessible root (shared documents, the
--      Director's private documents, templates, or the current map's folder).
--      Documents filed under other maps' folders are excluded, as are
--      documents already found via an info bubble.
--
-- Those documents can embed RichEncounter annotations -- the "encounter" rich
-- tag, see DocumentSystem/RichEncounter.lua -- and each RichEncounter wraps an
-- Encounter object. This returns a list of every such encounter found.
--
-- Each result entry is a table:
--   name          : string         the encounter's display name
--   encounter     : Encounter      the authored encounter
--   richEncounter : RichEncounter  the annotation wrapping the encounter
--   bubbleid      : string|nil     id of the info bubble it was found on, or
--                                  nil for game-wide journal entries
--   docid         : string|nil     id of the markdown document it was found in
function Encounter.GetEncountersOnCurrentMap()
    local result = {}
    local seenDocs = {}

    --Pull the RichEncounter annotations out of one journal markdown document.
    --Only consider annotations actually referenced by a rich tag in the
    --document text (in content order). This skips stale/orphaned annotations
    --that linger in the annotations table but no longer appear in the journal.
    local function HarvestDocument(markdownDoc, docid, bubbleid)
        if docid ~= nil then
            if seenDocs[docid] then
                return
            end
            seenDocs[docid] = true
        end

        for _, ref in ipairs(markdownDoc:GetReferencedAnnotations()) do
            local annotation = ref.annotation
            if type(annotation) == "table" and annotation.typeName == "RichEncounter" then
                local encounter = annotation:try_get("encounter")
                if encounter ~= nil then
                    result[#result + 1] = {
                        name = encounter:try_get("name", "Encounter"),
                        encounter = encounter,
                        richEncounter = annotation,
                        bubbleid = bubbleid,
                        docid = docid,
                    }
                end
            end
        end
    end

    --Info bubbles on the current map go first so they win default-encounter
    --inference in the combat setup dialog.
    local infoBubbles = dmhub.infoBubbles
    if infoBubbles ~= nil then
        for bubbleid, bubble in pairs(infoBubbles) do
            local infoDoc = bubble.document
            if infoDoc ~= nil then
                local markdownDoc = infoDoc:GetMarkdownDocument()
                if markdownDoc ~= nil then
                    HarvestDocument(markdownDoc, markdownDoc:try_get("id"), bubbleid)
                end
            end
        end
    end

    --Game-wide journal entries: every accessible markdown document in the
    --journal, sorted by name for a stable dropdown order.
    local docsTable = dmhub.GetTable(CustomDocument.tableName)
    if docsTable ~= nil then
        local accessibleRoots = CustomDocument.GetAccessibleRoots()
        local docs = {}
        for docid, doc in unhidden_pairs(docsTable) do
            if doc.typeName == "MarkdownDocument" and not seenDocs[docid] and CustomDocument.IsDocInAccessibleRoot(doc, accessibleRoots) then
                docs[#docs + 1] = { docid = docid, doc = doc }
            end
        end

        table.sort(docs, function(a, b)
            local nameA = a.doc.description or ""
            local nameB = b.doc.description or ""
            if nameA ~= nameB then
                return nameA < nameB
            end
            return a.docid < b.docid
        end)

        for _, entry in ipairs(docs) do
            HarvestDocument(entry.doc, entry.docid, nil)
        end
    end

    return result
end

-- ===========================================================================
-- Encounter Scripts
-- ===========================================================================
--
-- Encounter Scripts are user-authored Lua attached to an encounter. A script's
-- source code EVALUATES TO A DEFINITION TABLE (pure at load time, so the editor
-- can discover its parameters and victory condition without side effects):
--
--   return {
--       name = "Survive the Onslaught",
--       description = "The heroes win by surviving.",
--       params = {
--           { id = "rounds", name = "Rounds to Survive", type = "number",
--             default = 3, min = 1, max = 20 },
--       },
--       victory = {
--           text = function(ctx) return string.format("Survive %d Rounds", ctx.params.rounds) end,
--           check = function(ctx) return ctx.round > ctx.params.rounds end,
--       },
--       defeat = {
--           text = function(ctx) return "The Caravan is Destroyed" end,
--           check = function(ctx) return ctx.state.caravanDestroyed == true end,
--       },
--       onStart = function(ctx) end,  -- once, when combat begins
--       onRound = function(ctx) end,  -- once per round (including round 1)
--       think   = function(ctx) end,  -- every ~0.7s while combat is live
--       onEnd   = function(ctx) end,  -- once, when combat ends
--   }
--
-- victory replaces the encounter's built-in victory-condition dropdown; defeat
-- is script-only (the base game has no built-in defeat conditions). When a
-- defeat check passes, the director's initiative bar offers "Declare Defeat",
-- which announces the outcome and ends combat.
--
-- Condition text may be a string or function(ctx). It is resolved twice: at
-- edit time with a bare ctx (round 0, no queue) to produce the cached string
-- shown in the encounter builder, and - while combat is live - by the host
-- every heartbeat with the real ctx. The live result rides in the networked
-- script state, so progress text like "Survive 1/3 Rounds" updates on every
-- client without player clients ever executing script code.
--
-- Parameter types: "number" (min/max/default), "string", "boolean",
-- "choice" (options = {{id=..., text=...}, ...}), and "wave" (one of the
-- encounter's reinforcement waves; the value is the wave id).
--
-- Where things live:
--   * EncounterScript          - a library script stored in the
--                                "encounterScripts" object table, authored in
--                                the Compendium under Rules. Built-in starter
--                                scripts are registered in code (see the
--                                bottom of this section).
--   * EncounterScriptInstance  - an attachment on Encounter.scripts: a
--                                reference to a library/built-in script (or
--                                inline custom Lua) plus the director's chosen
--                                parameter values and a cached victory-text
--                                string.
--   * LiveEncounter.scriptStates - persisted per-instance runtime state
--                                (watermarks + the script's own ctx.state),
--                                riding in the networked initiative queue like
--                                deployedWaves/firedCues. This is what makes
--                                host handover and hot reload resume instead
--                                of refire.
--
-- Execution model: a 0.7s heartbeat (the same cadence as the initiative-bar
-- strips) runs on every client but only the ELECTED HOST fires handlers - the
-- lowest-sorting present director per dmhub.GetSessionInfo (NOT
-- dmhub.IsUserDM, which reflects the stale roster). Victory check functions
-- are pure reads and may run on any director client via CheckVictory; the
-- cached victory text is what player-facing surfaces display, so player
-- clients never execute encounter-script code.

--- @class EncounterScript
--- @field name string Display name of the library script.
--- @field description string What the script does, shown in pickers and the compendium.
--- @field code string The Lua source; must return a definition table.
EncounterScript = RegisterGameType("EncounterScript")

EncounterScript.name = "New Encounter Script"
EncounterScript.description = ""
EncounterScript.code = ""
EncounterScript.tableName = "encounterScripts"

function EncounterScript.OnDeserialize(self)
    if not self:has_key("guid") then
        self.guid = dmhub.GenerateGuid()
    end
end

--The seed code for a brand new custom or library script. Doubles as the
--reference documentation for the definition shape.
EncounterScript.starterTemplate = [==[
-- An Encounter Script. The code runs once to produce a definition table:
-- declare the parameters the director can edit in the encounter builder,
-- an optional custom victory condition, and the functions that run while
-- the encounter is live. Handlers run only on the host director's client.
--
-- ctx fields available in handlers:
--   ctx.params     resolved parameter values
--   ctx.state      persisted scratch table (survives reconnects; keep it small)
--   ctx.round      current round number
--   ctx.queue      the initiative queue
--   ctx.encounter  the LiveEncounter
-- ctx methods (call with ':'):
--   ctx:Announce(text)      send a chat message
--   ctx:DeployWave(waveid)  deploy one of the encounter's reinforcement waves
--   ctx:EnsureButton{...}   add a custom button to the Encounter Actions strip
--   ctx:DismissButton(id)   remove a custom button
--   ctx:Log(text)           print to the console
--   ctx:IsLive()            still in combat and still the host (for coroutines)

return {
    name = "My Encounter Script",
    description = "Describe what this script does.",

    params = {
        -- { id = "rounds", name = "Rounds", type = "number", default = 3, min = 1, max = 20 },
        -- { id = "announce", name = "Announce in Chat", type = "boolean", default = true },
        -- { id = "wave", name = "Wave to Deploy", type = "wave" },
    },

    -- Uncomment to replace the encounter's victory condition dropdown.
    -- text runs at edit time (ctx.queue == nil, ctx.round == 0) for the
    -- builder's cached label, and again on the host each heartbeat while
    -- combat is live, so it can show live progress like "Survive 1/3 Rounds":
    -- victory = {
    --     text = function(ctx) return string.format("Survive %d Rounds", ctx.params.rounds) end,
    --     check = function(ctx) return ctx.round > ctx.params.rounds end,
    -- },

    -- Uncomment to add a defeat condition (script-only; there are no built-in
    -- ones). When check passes the director can Declare Defeat, which
    -- announces the outcome and ends combat:
    -- defeat = {
    --     text = function(ctx) return "The Caravan is Destroyed" end,
    --     check = function(ctx) return ctx.state.caravanDestroyed == true end,
    -- },

    onStart = function(ctx)
    end,

    onRound = function(ctx)
    end,

    think = function(ctx)
    end,

    onEnd = function(ctx)
    end,
}
]==]

--- @return EncounterScript
function EncounterScript.CreateNew()
    return EncounterScript.new{
        guid = dmhub.GenerateGuid(),
        name = "New Encounter Script",
        description = "",
        code = EncounterScript.starterTemplate,
    }
end

--- Appends {id, text} entries for all library encounter scripts into options
--- (sorted by name).
function EncounterScript.FillDropdownOptions(options)
    local result = {}
    local dataTable = dmhub.GetTable(EncounterScript.tableName) or {}
    for k, item in unhidden_pairs(dataTable) do
        result[#result + 1] = {
            id = k,
            text = item.name,
        }
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    for _, item in ipairs(result) do
        options[#options + 1] = item
    end
end

-- ---------------------------------------------------------------------------
-- Built-in scripts
-- ---------------------------------------------------------------------------
-- Starter scripts shipped in code (repo-versioned, available in every game
-- without seeding the object table). They appear in the encounter builder's
-- Add Script picker; the compendium library holds game-authored scripts.

EncounterScript.builtins = {}
local g_builtinsById = {}

--info: { id, name, description, code }. id convention: "builtin:<slug>".
function EncounterScript.RegisterBuiltin(info)
    for i, existing in ipairs(EncounterScript.builtins) do
        if existing.id == info.id then
            EncounterScript.builtins[i] = info
            g_builtinsById[info.id] = info
            return
        end
    end
    EncounterScript.builtins[#EncounterScript.builtins + 1] = info
    g_builtinsById[info.id] = info
end

function EncounterScript.GetBuiltin(id)
    return g_builtinsById[id]
end

--- Appends built-in scripts, then library scripts, as {id, text} options.
--- Used by the encounter builder's Add Script picker.
function EncounterScript.FillPickerOptions(options)
    for _, builtin in ipairs(EncounterScript.builtins) do
        options[#options + 1] = { id = builtin.id, text = builtin.name .. " (built-in)" }
    end
    EncounterScript.FillDropdownOptions(options)
end

-- ---------------------------------------------------------------------------
-- Definition compilation + validation
-- ---------------------------------------------------------------------------

local g_paramTypes = {
    number = true,
    string = true,
    boolean = true,
    choice = true,
    wave = true,
}

--Validate and normalize a raw definition table returned by a script chunk.
--Returns the normalized definition, or nil + an error string.
local function NormalizeDefinition(def)
    local norm = {}

    if def.name ~= nil and type(def.name) ~= "string" then
        return nil, "name must be a string"
    end
    norm.name = def.name

    if def.description ~= nil and type(def.description) ~= "string" then
        return nil, "description must be a string"
    end
    norm.description = def.description

    norm.params = {}
    local seenIds = {}
    if def.params ~= nil then
        if type(def.params) ~= "table" then
            return nil, "params must be a list of parameter tables"
        end
        for i, p in ipairs(def.params) do
            if type(p) ~= "table" then
                return nil, string.format("params[%d] must be a table", i)
            end
            if type(p.id) ~= "string" or p.id == "" then
                return nil, string.format("params[%d] needs a string id", i)
            end
            if seenIds[p.id] then
                return nil, string.format("duplicate parameter id \"%s\"", p.id)
            end
            seenIds[p.id] = true
            local ptype = p.type or "string"
            if not g_paramTypes[ptype] then
                return nil, string.format("parameter \"%s\" has unknown type \"%s\"", p.id, tostring(ptype))
            end
            local param = {
                id = p.id,
                name = p.name or p.id,
                type = ptype,
                default = p.default,
                min = p.min,
                max = p.max,
            }
            if ptype == "choice" then
                if type(p.options) ~= "table" or #p.options == 0 then
                    return nil, string.format("choice parameter \"%s\" needs an options list", p.id)
                end
                param.options = {}
                for _, opt in ipairs(p.options) do
                    if type(opt) ~= "table" or opt.id == nil then
                        return nil, string.format("choice parameter \"%s\" has a malformed option", p.id)
                    end
                    param.options[#param.options + 1] = { id = opt.id, text = opt.text or tostring(opt.id) }
                end
            end
            norm.params[#norm.params + 1] = param
        end
    end

    if def.victory ~= nil then
        if type(def.victory) ~= "table" or type(def.victory.check) ~= "function" then
            return nil, "victory must be a table with a check function"
        end
        local text = def.victory.text
        if text ~= nil and type(text) ~= "string" and type(text) ~= "function" then
            return nil, "victory.text must be a string or a function"
        end
        norm.victory = { check = def.victory.check, text = text }
    end

    if def.defeat ~= nil then
        if type(def.defeat) ~= "table" or type(def.defeat.check) ~= "function" then
            return nil, "defeat must be a table with a check function"
        end
        local text = def.defeat.text
        if text ~= nil and type(text) ~= "string" and type(text) ~= "function" then
            return nil, "defeat.text must be a string or a function"
        end
        norm.defeat = { check = def.defeat.check, text = text }
    end

    for _, handler in ipairs({ "onStart", "onRound", "think", "onEnd" }) do
        local fn = def[handler]
        if fn ~= nil and type(fn) ~= "function" then
            return nil, handler .. " must be a function"
        end
        norm[handler] = fn
    end

    return norm
end

--Compiled-definition cache, keyed by the exact source string. Definitions are
--pure (no side effects at load), so identical source always yields the same
--definition; callers must treat the returned table as read-only.
local g_definitionCache = {}

--- Compile encounter-script source into a normalized definition table.
--- Follows the AbilityScript.lua precedent: load(code, name, "t", env) with an
--- environment that reads globals but keeps writes local to the chunk.
--- @param code string
--- @return table|nil, string|nil definition, error
function EncounterScript.CompileDefinition(code)
    if code == nil or code == "" then
        return nil, "The script is empty"
    end

    local cached = g_definitionCache[code]
    if cached ~= nil then
        return cached.def, cached.error
    end

    local result = { def = nil, error = nil }
    g_definitionCache[code] = result

    local env = setmetatable({}, { __index = _G })
    local chunk, err = load(code, "EncounterScript", "t", env)
    if chunk == nil then
        result.error = "Compile error: " .. tostring(err)
        return nil, result.error
    end

    local ok, def = pcall(chunk)
    if not ok then
        result.error = "Error running script: " .. tostring(def)
        return nil, result.error
    end
    if type(def) ~= "table" then
        result.error = "The script must return a definition table"
        return nil, result.error
    end

    local norm, normErr = NormalizeDefinition(def)
    if norm == nil then
        result.error = "Invalid definition: " .. tostring(normErr)
        return nil, result.error
    end

    result.def = norm
    return norm, nil
end

--- Human-readable summary of what a definition declares, for editor status rows.
function EncounterScript.DescribeDefinition(def)
    local parts = {}
    if #def.params == 1 then
        parts[#parts + 1] = "1 parameter"
    elseif #def.params > 1 then
        parts[#parts + 1] = string.format("%d parameters", #def.params)
    end
    if def.victory ~= nil then
        parts[#parts + 1] = "custom victory condition"
    end
    if def.defeat ~= nil then
        parts[#parts + 1] = "custom defeat condition"
    end
    local handlers = {}
    for _, handler in ipairs({ "onStart", "onRound", "think", "onEnd" }) do
        if def[handler] ~= nil then
            handlers[#handlers + 1] = handler
        end
    end
    if #handlers > 0 then
        parts[#parts + 1] = "runs " .. table.concat(handlers, ", ")
    end
    if #parts == 0 then
        return "Definition OK (declares nothing yet)"
    end
    return "Definition OK: " .. table.concat(parts, "; ")
end

-- ---------------------------------------------------------------------------
-- EncounterScriptInstance: a script attached to an encounter
-- ---------------------------------------------------------------------------

--- @class EncounterScriptInstance
--- @field scriptid string Id into the encounterScripts table or a "builtin:" id; "" = inline custom code.
--- @field code string Inline Lua source (custom scripts only).
--- @field name string Cached display name, refreshed from the definition at edit time.
--- @field params table {paramid = value} chosen by the director.
--- @field victoryText string|nil Cached resolved victory text (edit-time snapshot; what players see).
--- @field defeatText string|nil Cached resolved defeat text (edit-time snapshot; what players see).
EncounterScriptInstance = RegisterGameType("EncounterScriptInstance")

EncounterScriptInstance.scriptid = ""
EncounterScriptInstance.code = ""
EncounterScriptInstance.name = "Encounter Script"
EncounterScriptInstance.params = {}

function EncounterScriptInstance.OnDeserialize(self)
    if not self:has_key("guid") then
        self.guid = dmhub.GenerateGuid()
    end
end

--- Attach a library or built-in script by id.
function EncounterScriptInstance.CreateFromLibrary(scriptid)
    local result = EncounterScriptInstance.new{
        guid = dmhub.GenerateGuid(),
        scriptid = scriptid,
        params = {},
    }
    result:RefreshCache()
    return result
end

--- Attach a new inline custom script seeded with the starter template.
function EncounterScriptInstance.CreateCustom()
    local result = EncounterScriptInstance.new{
        guid = dmhub.GenerateGuid(),
        scriptid = "",
        code = EncounterScript.starterTemplate,
        name = "Custom Script",
        params = {},
    }
    result:RefreshCache()
    return result
end

--True when this instance carries inline code rather than a library reference.
function EncounterScriptInstance:IsCustom()
    return self:try_get("scriptid", "") == ""
end

--- Resolve this instance's source code. Returns code, or nil + error when the
--- referenced library script is missing/deleted.
function EncounterScriptInstance:GetCode()
    local sid = self:try_get("scriptid", "")
    if sid == "" then
        return self:try_get("code", ""), nil
    end

    local builtin = EncounterScript.GetBuiltin(sid)
    if builtin ~= nil then
        return builtin.code, nil
    end

    local dataTable = dmhub.GetTable(EncounterScript.tableName) or {}
    local item = dataTable[sid]
    if item == nil or item:try_get("hidden", false) then
        return nil, "Script not found in library"
    end
    return item:try_get("code", ""), nil
end

--- Resolve + compile this instance's definition.
--- @return table|nil, string|nil definition, error
function EncounterScriptInstance:GetDefinition()
    local code, err = self:GetCode()
    if code == nil then
        return nil, err
    end
    return EncounterScript.CompileDefinition(code)
end

--- The director's parameter values with defaults applied and values coerced to
--- their declared types. def is optional (resolved when absent).
function EncounterScriptInstance:ResolveParams(def)
    local result = {}
    if def == nil then
        def = select(1, self:GetDefinition())
    end
    if def == nil then
        return result
    end

    local values = self:try_get("params", {})
    for _, param in ipairs(def.params) do
        local v = values[param.id]
        if v == nil then
            v = param.default
        end
        if param.type == "number" then
            v = tonumber(v) or 0
            if param.min ~= nil and v < param.min then v = param.min end
            if param.max ~= nil and v > param.max then v = param.max end
        elseif param.type == "boolean" then
            v = (v == true)
        elseif param.type == "string" then
            if v == nil then v = "" end
            v = tostring(v)
        elseif param.type == "choice" then
            local valid = false
            for _, opt in ipairs(param.options or {}) do
                if opt.id == v then
                    valid = true
                    break
                end
            end
            if not valid and param.options ~= nil and #param.options > 0 then
                v = param.options[1].id
            end
        end
        --"wave" values stay as the stored wave id (or nil when unset).
        result[param.id] = v
    end
    return result
end

--Evaluate a victory/defeat condition's text with an edit-time context (cond is
--def.victory or def.defeat). Returns a string or nil. Falls back to the
--definition/instance name when no text is declared, so a condition-declaring
--script always yields a displayable label.
local function EvaluateConditionText(instance, def, cond)
    if def == nil or cond == nil then
        return nil
    end
    local text = cond.text
    if type(text) == "string" then
        return text
    end
    if type(text) == "function" then
        local ctx = {
            params = instance:ResolveParams(def),
            state = {},
            round = 0,
            queue = nil,
            encounter = nil,
        }
        local ok, result = pcall(text, ctx)
        if ok and type(result) == "string" and result ~= "" then
            return result
        end
    end
    return def.name or instance:try_get("name", "Encounter Script")
end

--- Refresh the cached display name and victory text from the definition.
--- Called at edit time (attach, param change, editor open) on the authoring
--- director's client. Read-only surfaces consume the cached strings so they
--- never execute script code.
function EncounterScriptInstance:RefreshCache()
    local def = select(1, self:GetDefinition())
    if def == nil then
        --broken or missing script: keep the last known name, but never let a
        --stale victory/defeat text keep driving the condition UI.
        if self:has_key("victoryText") then
            self.victoryText = nil
        end
        if self:has_key("defeatText") then
            self.defeatText = nil
        end
        return
    end
    if def.name ~= nil and def.name ~= "" then
        self.name = def.name
    end
    if def.victory ~= nil then
        self.victoryText = EvaluateConditionText(self, def, def.victory)
    elseif self:has_key("victoryText") then
        self.victoryText = nil
    end
    if def.defeat ~= nil then
        self.defeatText = EvaluateConditionText(self, def, def.defeat)
    elseif self:has_key("defeatText") then
        self.defeatText = nil
    end
end

-- ---------------------------------------------------------------------------
-- Encounter accessors
-- ---------------------------------------------------------------------------

function Encounter:GetScripts()
    return self:try_get("scripts", {})
end

--Attach a script instance. Copy-on-write like AddWave so the shared class
--default is never mutated.
function Encounter:AddScript(instance)
    local scripts = DeepCopy(self:try_get("scripts", {}))
    scripts[#scripts + 1] = instance
    self.scripts = scripts
end

--Detach a script instance by guid.
function Encounter:RemoveScript(guid)
    local scripts = self:try_get("scripts")
    if scripts == nil then
        return
    end
    local result = {}
    for _, instance in ipairs(scripts) do
        if instance:try_get("guid") ~= guid then
            result[#result + 1] = instance
        end
    end
    self.scripts = result
end

--- The cached victory text of the first attached script that declares a
--- victory condition, or nil. This is the CACHED string (safe on player
--- clients); the live check is GetScriptVictory/EvaluateVictoryCheck.
--- @return string|nil, table|nil text, instance
function Encounter:ScriptVictoryText()
    for _, instance in ipairs(self:try_get("scripts", {})) do
        local text = instance:try_get("victoryText")
        if text ~= nil and text ~= "" then
            return text, instance
        end
    end
    return nil
end

--- The first attached script instance whose (live, compiled) definition
--- declares a victory condition. Director-side only: this compiles and runs
--- script code. Returns instance, definition or nil.
function Encounter:GetScriptVictory()
    for _, instance in ipairs(self:try_get("scripts", {})) do
        local def = select(1, instance:GetDefinition())
        if def ~= nil and def.victory ~= nil then
            return instance, def
        end
    end
    return nil
end

--- The cached defeat text of the first attached script that declares a defeat
--- condition, or nil. Like ScriptVictoryText this is the CACHED string (safe
--- on player clients); the live check is GetScriptDefeat/EvaluateDefeatCheck.
--- @return string|nil, table|nil text, instance
function Encounter:ScriptDefeatText()
    for _, instance in ipairs(self:try_get("scripts", {})) do
        local text = instance:try_get("defeatText")
        if text ~= nil and text ~= "" then
            return text, instance
        end
    end
    return nil
end

--- The first attached script instance whose (live, compiled) definition
--- declares a defeat condition. Director-side only: this compiles and runs
--- script code. Returns instance, definition or nil.
function Encounter:GetScriptDefeat()
    for _, instance in ipairs(self:try_get("scripts", {})) do
        local def = select(1, instance:GetDefinition())
        if def ~= nil and def.defeat ~= nil then
            return instance, def
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- LiveEncounter script state
-- ---------------------------------------------------------------------------

--Persisted per-instance runtime state, keyed by instance guid:
--  { started = bool, ended = bool, lastRound = number, state = {} }
--started/ended/lastRound are the runtime's fire-once watermarks; state is the
--script's own ctx.state scratch table. Rides in the networked queue like
--deployedWaves/firedCues (copy-on-write + upload), which is what lets an
--elected-host handover or a hot reload resume instead of refiring handlers.
LiveEncounter.scriptStates = {}

function LiveEncounter:GetScriptState(guid)
    local states = self:try_get("scriptStates")
    if states == nil then
        return nil
    end
    return states[guid]
end

--Callers must network the change afterwards (the runtime batches one upload
--per heartbeat).
function LiveEncounter:SetScriptState(guid, state)
    local states = DeepCopy(self:try_get("scriptStates", {}))
    states[guid] = state
    self.scriptStates = states
end

--Live-combat overrides of the cached-text accessors: prefer the text the host
--resolved this combat (updated each heartbeat with the real round/state and
--persisted in scriptStates), falling back to the edit-time cache until the
--host's first tick lands. Player clients read these networked strings, so
--they still never execute script code.
function LiveEncounter:ScriptVictoryText()
    local text, instance = Encounter.ScriptVictoryText(self)
    if instance ~= nil then
        local st = self:GetScriptState(instance:try_get("guid", ""))
        if st ~= nil and type(st.victoryText) == "string" and st.victoryText ~= "" then
            return st.victoryText, instance
        end
    end
    return text, instance
end

function LiveEncounter:ScriptDefeatText()
    local text, instance = Encounter.ScriptDefeatText(self)
    if instance ~= nil then
        local st = self:GetScriptState(instance:try_get("guid", ""))
        if st ~= nil and type(st.defeatText) == "string" and st.defeatText ~= "" then
            return st.defeatText, instance
        end
    end
    return text, instance
end

-- ---------------------------------------------------------------------------
-- Victory check evaluation (any director client)
-- ---------------------------------------------------------------------------

--Once-per-distinct-message error reporting so a broken script does not flood
--the console at heartbeat cadence. Cleared when the queue changes.
local g_scriptErrorsPrinted = {}

local function PrintScriptError(instance, message)
    local name = "Encounter Script"
    if instance ~= nil then
        name = instance:try_get("name", name)
    end
    local text = string.format("Encounter Script '%s': %s", name, tostring(message))
    if g_scriptErrorsPrinted[text] then
        return
    end
    g_scriptErrorsPrinted[text] = true
    dmhub.CloudError(text)
    print("ERROR:", text)
end

--A read-only context for victory check functions: same shape as the handler
--ctx but with side-effecting methods stubbed out, since check runs at poll
--cadence on every director client and must stay pure.
local function MakeReadContext(liveEncounter, instance, def)
    local ctx = {
        params = instance:ResolveParams(def),
        state = {},
        round = 0,
        queue = nil,
        encounter = liveEncounter,
        isHost = false,
    }

    local q = dmhub.initiativeQueue
    if q ~= nil then
        ctx.queue = q
        ctx.round = q.round or 0
    end

    local guid = instance:try_get("guid", "")
    local persisted = liveEncounter:GetScriptState(guid)
    if persisted ~= nil and persisted.state ~= nil then
        ctx.state = DeepCopy(persisted.state)
    end

    ctx.Log = function(_, text)
        print(string.format("EncounterScript '%s': %s", instance:try_get("name", "script"), tostring(text)))
    end
    local NotAllowed = function()
        PrintScriptError(instance, "victory/defeat check functions must be pure; use onRound/think for side effects")
        return false
    end
    ctx.Announce = NotAllowed
    ctx.DeployWave = NotAllowed
    ctx.EnsureButton = NotAllowed
    ctx.DismissButton = NotAllowed
    ctx.IsLive = function() return false end

    return ctx
end

--Shared victory/defeat check evaluation. pcall-guarded: errors report once and
--count as "condition not met" so a broken script can never accidentally end a
--fight (in either direction).
local function EvaluateConditionCheck(liveEncounter, instance, def, checkFn, label)
    local ctx = MakeReadContext(liveEncounter, instance, def)
    local ok, result = pcall(checkFn, ctx)
    if not ok then
        PrintScriptError(instance, label .. " check error: " .. tostring(result))
        return false
    end
    return result == true
end

--- Evaluate a script's victory check.
function EncounterScript.EvaluateVictoryCheck(liveEncounter, instance, def)
    return EvaluateConditionCheck(liveEncounter, instance, def, def.victory.check, "victory")
end

--- Evaluate a script's defeat check.
function EncounterScript.EvaluateDefeatCheck(liveEncounter, instance, def)
    return EvaluateConditionCheck(liveEncounter, instance, def, def.defeat.check, "defeat")
end

-- ---------------------------------------------------------------------------
-- Host election
-- ---------------------------------------------------------------------------

--Presence per the director-election reference: dmhub.GetSessionInfo(uid).dm is
--the authoritative live director flag (dmhub.IsUserDM reflects the persisted
--roster and lies); ghost sessions report loggedOut == false with a huge
--timeSinceLastContact, so both checks are required. 140s matches Audio.lua.
local function IsDirectorPresent(userid)
    local info = nil
    pcall(function() info = dmhub.GetSessionInfo(userid) end)
    if info == nil or info.loggedOut then
        return false
    end
    local isdm = false
    pcall(function() isdm = (info.dm == true) end)
    return isdm and (info.timeSinceLastContact or 0) < 140
end

--Lowest-sorting present director wins; every client computes the same answer
--from the same shared presence data. Falls back to acting when presence is
--unreadable or nobody looks present - a stalled encounter script is worse
--than a rare duplicate.
local function IsElectedHost()
    if not dmhub.isDM then
        return false
    end
    local best = nil
    for _, uid in ipairs(dmhub.users or {}) do
        if IsDirectorPresent(uid) and (best == nil or uid < best) then
            best = uid
        end
    end
    if best == nil then
        return true
    end
    return best == dmhub.userid
end

-- ---------------------------------------------------------------------------
-- Host runtime: the handler ctx and the heartbeat driver
-- ---------------------------------------------------------------------------

local g_runtime = {
    queueGuid = nil,
    contexts = {},
}

--The full handler context for the elected host. queue/encounter/round/state
--are re-pointed by the driver each heartbeat; methods are stable closures.
local function MakeHostContext(instance)
    local ctx = {
        params = {},
        state = {},
        round = 0,
        queue = nil,
        encounter = nil,
        isHost = true,
    }

    local createdForQueue = g_runtime.queueGuid

    ctx.IsLive = function()
        if mod.unloaded then
            return false
        end
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            return false
        end
        if tostring(q:try_get("guid")) ~= tostring(createdForQueue) then
            return false
        end
        return IsElectedHost()
    end

    ctx.Announce = function(_, text)
        pcall(function() chat.Send(tostring(text)) end)
    end

    ctx.Log = function(_, text)
        print(string.format("EncounterScript '%s': %s", instance:try_get("name", "script"), tostring(text)))
    end

    --Deploy one of the encounter's authored reinforcement waves right now.
    --DeployWave itself marks the wave deployed, so a lost ctx.state can never
    --double-deploy. Returns true if the wave deployed.
    ctx.DeployWave = function(_, waveid)
        if waveid == nil or waveid == "" then
            return false
        end
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            return false
        end
        local liveEncounter = q:try_get("liveEncounter")
        if type(liveEncounter) ~= "table" then
            return false
        end
        if liveEncounter:IsWaveDeployed(waveid) then
            return false
        end
        liveEncounter:DeployWave(waveid, q)
        dmhub:UploadInitiativeQueue()
        return true
    end

    --Custom buttons on the Encounter Actions strip, namespaced by instance so
    --two copies of the same script cannot collide.
    ctx.EnsureButton = function(_, button)
        if type(button) ~= "table" then
            return false
        end
        button = DeepCopy(button)
        button.id = string.format("%s:%s", instance:try_get("guid", "script"), tostring(button.id or "button"))
        return LiveEncounter.EnsureCustomButton(button)
    end

    ctx.DismissButton = function(_, buttonid)
        return LiveEncounter.DismissCustomButton(string.format("%s:%s", instance:try_get("guid", "script"), tostring(buttonid or "button")))
    end

    return ctx
end

--Resolve a victory/defeat condition's display text against the live host ctx.
--Returns nil (rather than a name fallback) when nothing resolves, so callers
--keep the previous/edit-time text instead of degrading it.
local function ResolveLiveConditionText(cond, ctx)
    if cond == nil then
        return nil
    end
    local text = cond.text
    if type(text) == "string" then
        return text
    end
    if type(text) == "function" then
        local ok, result = pcall(text, ctx)
        if ok and type(result) == "string" and result ~= "" then
            return result
        end
    end
    return nil
end

--Run one script instance for one heartbeat. Returns true when its persisted
--state changed (the caller batches the upload). isLive is false once combat
--has ended (queue hidden) - that is when onEnd fires.
local function RunInstanceTick(liveEncounter, instance, q, isLive)
    local guid = instance:try_get("guid", "")
    if guid == "" then
        return false
    end

    local def, err = instance:GetDefinition()
    if def == nil then
        PrintScriptError(instance, err)
        return false
    end

    local persisted = liveEncounter:GetScriptState(guid)
    local st = DeepCopy(persisted or { started = false, ended = false, lastRound = 0, state = {} })
    if st.state == nil then
        st.state = {}
    end
    local ok, before = pcall(dmhub.ToJson, st)
    if not ok then
        before = nil
    end

    local ctx = g_runtime.contexts[guid]
    if ctx == nil then
        ctx = MakeHostContext(instance)
        g_runtime.contexts[guid] = ctx
    end
    ctx.params = instance:ResolveParams(def)
    ctx.queue = q
    ctx.encounter = liveEncounter
    ctx.round = q.round or 0
    ctx.state = st.state

    local function Fire(fn)
        if fn == nil then
            return
        end
        local fnOk, fnErr = pcall(fn, ctx)
        if not fnOk then
            PrintScriptError(instance, tostring(fnErr))
        end
    end

    if isLive then
        --watermarks flip BEFORE the handler fires so an erroring handler does
        --not refire every heartbeat.
        if not st.started then
            st.started = true
            Fire(def.onStart)
        end
        local round = q.round or 0
        if round > (st.lastRound or 0) then
            --only the current round fires; rounds that elapsed while no host
            --was present are not replayed as a backlog.
            st.lastRound = round
            Fire(def.onRound)
        end
        Fire(def.think)
    else
        if st.started and not st.ended then
            st.ended = true
            Fire(def.onEnd)
        end
    end

    st.state = ctx.state

    --Re-resolve the victory/defeat display text with the real combat context
    --(post-handlers, so this tick's state changes are reflected). The strings
    --ride in the networked script state; ScriptVictoryText/ScriptDefeatText
    --on LiveEncounter prefer them, which is how "Survive 1/3 Rounds"-style
    --progress updates on every client.
    if isLive then
        st.victoryText = ResolveLiveConditionText(def.victory, ctx) or st.victoryText
        st.defeatText = ResolveLiveConditionText(def.defeat, ctx) or st.defeatText
    end

    local afterOk, after = pcall(dmhub.ToJson, st)
    if not afterOk then
        PrintScriptError(instance, "ctx.state must contain only serializable values")
        return false
    end
    if after ~= before then
        liveEncounter:SetScriptState(guid, st)
        return true
    end
    return false
end

local function DriverTick()
    local q = dmhub.initiativeQueue
    if q == nil then
        return
    end

    local queueGuid = tostring(q:try_get("guid"))
    if queueGuid ~= g_runtime.queueGuid then
        g_runtime.queueGuid = queueGuid
        g_runtime.contexts = {}
        g_scriptErrorsPrinted = {}
    end

    local liveEncounter = q:try_get("liveEncounter")
    if type(liveEncounter) ~= "table" then
        return
    end

    local scripts = liveEncounter:GetScripts()
    if #scripts == 0 then
        return
    end

    if not IsElectedHost() then
        return
    end

    local isLive = not q.hidden
    local dirty = false
    for _, instance in ipairs(scripts) do
        local ok, changed = pcall(RunInstanceTick, liveEncounter, instance, q, isLive)
        if ok then
            dirty = dirty or (changed == true)
        else
            PrintScriptError(instance, tostring(changed))
        end
    end

    if dirty then
        dmhub:UploadInitiativeQueue()
    end
end

--The heartbeat: 0.7s, matching the initiative-bar strips. Runs on every
--client; DriverTick gates on the election. The Schedule chain (rather than a
--single long coroutine) guarantees ticks never overlap and dies cleanly on
--hot reload via mod.unloaded.
local function ScheduleDriver()
    dmhub.Schedule(0.7, function()
        if mod.unloaded then
            return
        end
        pcall(DriverTick)
        ScheduleDriver()
    end)
end

ScheduleDriver()

-- ---------------------------------------------------------------------------
-- Code editing UI (shared by the attachment dialog and the compendium page)
-- ---------------------------------------------------------------------------

--A code-editing block: monospace multiline input, a live compile-status row,
--and an "Open in External Editor" button (DiceStudio's round-trip pattern).
--options:
--  width        : block width (default 700)
--  height       : code area height (default 340)
--  filenameHint : used for the external editor's temp filename
--  getText      : function() -> current code
--  setText      : function(newCode) called whenever the code changes
function EncounterScript.CreateCodePanel(options)
    options = options or {}

    local watcher = nil
    local function DestroyWatcher()
        if watcher ~= nil then
            pcall(function() watcher:Destroy() end)
            watcher = nil
        end
    end

    local statusLabel = gui.Label{
        classes = { "fgMuted" },
        fontSize = 12,
        width = "100%",
        height = "auto",
        textWrap = true,
        vmargin = 4,
        text = "",
        refreshCode = function(element)
            local code = options.getText()
            local def, err = EncounterScript.CompileDefinition(code)
            if def == nil then
                element.text = tostring(err)
            else
                element.text = EncounterScript.DescribeDefinition(def)
            end
        end,
    }

    local codeInput = gui.Input{
        fontFace = "Courier",
        fontSize = 12,
        width = "100%",
        height = "auto",
        minHeight = (options.height or 340) - 10,
        halign = "left",
        multiline = true,
        textAlignment = "topleft",
        characterLimit = 20000,
        text = options.getText() or "",
        change = function(element)
            options.setText(element.text)
            statusLabel:FireEvent("refreshCode")
        end,
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = options.width or 700,
        height = "auto",
        flow = "vertical",

        destroy = function(element)
            DestroyWatcher()
        end,

        create = function(element)
            statusLabel:FireEvent("refreshCode")
        end,

        --the external editor (or any other writer) changed the code out from
        --under the input; reflect it.
        refreshExternal = function(element)
            codeInput.text = options.getText() or ""
            statusLabel:FireEvent("refreshCode")
        end,

        gui.Panel{
            classes = { "bordered" },
            width = "100%",
            height = options.height or 340,
            vscroll = true,
            borderBox = true,
            codeInput,
        },

        statusLabel,

        gui.Button{
            text = "Open in External Editor",
            width = 220,
            height = 26,
            fontSize = 14,
            halign = "left",
            vmargin = 4,
            click = function(element)
                DestroyWatcher()
                --OpenTextFileInConnectedEditor caps filenames at 48 chars and
                --returns nil past it. filenameHint is a 36-char data-table GUID,
                --so the full "encounterscript-<guid>.lua" (56 chars) always
                --overflowed. Keep the prefix short and truncate the hint so the
                --result stays well under the limit.
                local hint = tostring(options.filenameHint or "script")
                if #hint > 24 then
                    hint = hint:sub(1, 24)
                end
                local filename = string.format("encounter-%s.lua", hint)
                watcher = dmhub.OpenTextFileInConnectedEditor(filename, options.getText() or "", function(contents)
                    if mod.unloaded or not resultPanel.valid then
                        return
                    end
                    options.setText(contents)
                    resultPanel:FireEvent("refreshExternal")
                end)
                if watcher == nil then
                    gui.ModalMessage{
                        title = "Could not open editor",
                        message = "Could not spawn an external text editor for the encounter script.",
                    }
                end
            end,
        },
    }

    return resultPanel
end

--The modal editor for an attachment's custom Lua. options:
--  title            : dialog title (default "Encounter Script")
--  code             : initial code
--  filenameHint     : external-editor temp filename hint
--  onSave           : function(newCode) - called when Save is pressed
--  canSaveToLibrary : offer the "Save to Library..." button
--  onSavedToLibrary : function(scriptid) - called after the library item is
--                     created (the dialog closes afterwards)
function EncounterScript.ShowCodeEditorDialog(options)
    options = options or {}
    local currentCode = options.code or ""

    local codePanel = EncounterScript.CreateCodePanel{
        width = "100%",
        height = 380,
        filenameHint = options.filenameHint,
        getText = function() return currentCode end,
        setText = function(text) currentCode = text end,
    }

    local buttons = {}

    buttons[#buttons + 1] = gui.Button{
        text = "Cancel",
        width = 120,
        height = 30,
        fontSize = 16,
        hmargin = 6,
        click = function(element)
            gui.CloseModal()
        end,
    }

    if options.canSaveToLibrary then
        buttons[#buttons + 1] = gui.Button{
            text = "Save to Library...",
            width = 180,
            height = 30,
            fontSize = 16,
            hmargin = 6,
            click = function(element)
                local def, err = EncounterScript.CompileDefinition(currentCode)
                if def == nil then
                    gui.ModalMessage{
                        title = "Cannot save to library",
                        message = tostring(err),
                    }
                    return
                end
                local item = EncounterScript.new{
                    guid = dmhub.GenerateGuid(),
                    name = def.name or "New Encounter Script",
                    description = def.description or "",
                    code = currentCode,
                }
                local scriptid = dmhub.SetAndUploadTableItem(EncounterScript.tableName, item)
                if options.onSavedToLibrary ~= nil then
                    options.onSavedToLibrary(scriptid)
                end
                gui.CloseModal()
            end,
        }
    end

    buttons[#buttons + 1] = gui.Button{
        text = "Save",
        width = 120,
        height = 30,
        fontSize = 16,
        hmargin = 6,
        click = function(element)
            if options.onSave ~= nil then
                options.onSave(currentCode)
            end
            gui.CloseModal()
        end,
    }

    local dialog = gui.Panel{
        classes = { "framedPanel" },
        styles = ThemeEngine.GetStyles(),
        bgimage = true,
        width = 820,
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "vertical",
        pad = 16,
        borderBox = true,

        gui.Label{
            classes = { "bold" },
            fontSize = 22,
            width = "100%",
            height = "auto",
            bmargin = 8,
            text = options.title or "Encounter Script",
        },

        codePanel,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            tmargin = 10,
            children = buttons,
        },
    }

    gui.ShowModal(dialog)
end

-- ---------------------------------------------------------------------------
-- Compendium page (Rules > Encounter Scripts)
-- ---------------------------------------------------------------------------

local UploadScriptWithId = function(id)
    local dataTable = dmhub.GetTable(EncounterScript.tableName) or {}
    if dataTable[id] ~= nil then
        dmhub.SetAndUploadTableItem(EncounterScript.tableName, dataTable[id])
    end
end

local ScriptCompendiumSetData = function(tableName, scriptPanel, keyid)
    local dataTable = dmhub.GetTable(tableName) or {}
    local script = dataTable[keyid]
    if script == nil then
        return
    end
    local UploadScript = function()
        dmhub.SetAndUploadTableItem(tableName, script)
    end

    --if we were displaying a different script and it has unsaved changes, flush it.
    if scriptPanel.data.keyid ~= "" and scriptPanel.data.keyid ~= keyid and dmhub.ToJson(dataTable[scriptPanel.data.keyid]) ~= scriptPanel.data.scriptjson then
        UploadScriptWithId(scriptPanel.data.keyid)
    end

    scriptPanel.data.keyid = keyid
    scriptPanel.data.scriptjson = dmhub.ToJson(script)

    local children = {}

    if devmode() then
        children[#children + 1] = gui.Panel{
            classes = { "formStackedRow" },
            gui.Label{
                classes = { "formStacked" },
                text = "ID:",
            },
            gui.Input{
                classes = { "formStacked" },
                text = script.id,
                editable = false,
            },
        }
    end

    children[#children + 1] = gui.Panel{
        classes = { "formStackedRow" },
        gui.Label{
            classes = { "formStacked" },
            text = "Name:",
        },
        gui.Input{
            classes = { "formStacked" },
            text = script.name,
            change = function(element)
                script.name = element.text
                UploadScript()
            end,
        },
    }

    children[#children + 1] = gui.Panel{
        classes = { "formStackedRow" },
        gui.Label{
            classes = { "formStacked" },
            text = "Details:",
        },
        gui.Input{
            classes = { "formStacked" },
            text = script.description,
            multiline = true,
            textAlignment = "topLeft",
            height = 60,
            characterLimit = 600,
            change = function(element)
                script.description = element.text
                UploadScript()
            end,
        },
    }

    children[#children + 1] = EncounterScript.CreateCodePanel{
        width = 800,
        height = 420,
        filenameHint = keyid,
        getText = function()
            return script:try_get("code", "")
        end,
        setText = function(text)
            script.code = text
            UploadScript()
        end,
    }

    scriptPanel.children = children
end

function EncounterScript.CreateEditor()
    local scriptPanel
    scriptPanel = gui.Panel{
        data = {
            SetData = function(tableName, keyid)
                ScriptCompendiumSetData(tableName, scriptPanel, keyid)
            end,
            keyid = "",
            scriptjson = "",
        },
        destroy = function(element)
            local dataTable = dmhub.GetTable(EncounterScript.tableName) or {}
            if element.data.keyid ~= "" and dataTable[element.data.keyid] ~= nil and dmhub.ToJson(dataTable[element.data.keyid]) ~= element.data.scriptjson then
                UploadScriptWithId(element.data.keyid)
            end
        end,
        vscroll = true,
        width = 1200,
        height = "90%",
        halign = "left",
        flow = "vertical",
        pad = 20,
        borderBox = true,
    }

    return scriptPanel
end

local ShowEncounterScriptsPanel = function(contentPanel)
    local scriptPanel = EncounterScript.CreateEditor()
    local SetData = scriptPanel.data.SetData

    local listItems = {}

    local itemsListPanel
    itemsListPanel = gui.Panel{
        classes = { "list-panel" },
        vscroll = true,
        monitorAssets = true,
        refreshAssets = function(element)
            local children = {}
            local dataTable = dmhub.GetTable(EncounterScript.tableName) or {}
            local newListItems = {}

            for k, item in pairs(dataTable) do
                newListItems[k] = listItems[k] or Compendium.CreateListItem{
                    select = element.aliveTime > 0.2,
                    tableName = EncounterScript.tableName,
                    key = k,
                    click = function()
                        SetData(EncounterScript.tableName, k)
                    end,
                }

                newListItems[k].text = item.name

                children[#children + 1] = newListItems[k]
            end

            table.sort(children, function(a, b) return a.text < b.text end)

            listItems = newListItems
            itemsListPanel.children = children
        end,
    }

    itemsListPanel:FireEvent("refreshAssets")

    local leftPanel = gui.Panel{
        selfStyle = {
            flow = "vertical",
            height = "100%",
            width = "auto",
        },

        itemsListPanel,
        Compendium.AddButton{
            click = function(element)
                dmhub.SetAndUploadTableItem(EncounterScript.tableName, EncounterScript.CreateNew())
            end,
        },
    }

    contentPanel.children = { leftPanel, scriptPanel }
end

Compendium.Register{
    section = "Rules",
    text = "Encounter Scripts",
    contentType = EncounterScript.tableName,
    click = function(contentPanel)
        ShowEncounterScriptsPanel(contentPanel)
    end,
}

-- ---------------------------------------------------------------------------
-- Built-in starter scripts
-- ---------------------------------------------------------------------------
-- These double as the tutorial: pick one in the encounter builder, read its
-- code from the compendium-adjacent "(built-in)" picker entries, or use
-- Custom Lua Script and crib from them.

EncounterScript.RegisterBuiltin{
    id = "builtin:survive-rounds",
    name = "Survive the Onslaught",
    description = "The heroes win by surviving: victory at the end of a chosen round.",
    code = [==[
return {
    name = "Survive the Onslaught",
    description = "The heroes win by surviving: victory at the end of a chosen round.",

    params = {
        { id = "rounds", name = "Rounds to Survive", type = "number", default = 3, min = 1, max = 20 },
        { id = "announce", name = "Announce Rounds in Chat", type = "boolean", default = true },
    },

    victory = {
        text = function(ctx)
            return string.format("Survive %d Rounds", ctx.params.rounds)
        end,
        --the round counter advances past the target once the final round
        --completes, which is the moment the heroes have survived it.
        check = function(ctx)
            return ctx.round > ctx.params.rounds
        end,
    },

    onRound = function(ctx)
        if not ctx.params.announce then
            return
        end
        local remaining = ctx.params.rounds - ctx.round + 1
        if remaining > 1 then
            ctx:Announce(string.format("Round %d: survive %d more rounds!", ctx.round, remaining))
        elseif remaining == 1 then
            ctx:Announce(string.format("Round %d: survive this round to win!", ctx.round))
        end
    end,
}
]==],
}

EncounterScript.RegisterBuiltin{
    id = "builtin:advancing-hazard",
    name = "Advancing Hazard",
    description = "Each round from round 2 on, Targetable map objects with the chosen keyword advance a number of squares in a direction.",
    code = [==[
return {
    name = "Advancing Hazard",
    description = "Each round from round 2 on, Targetable map objects with the chosen keyword advance a number of squares in a direction. Give the hazard object the Targetable property and a keyword.",

    params = {
        { id = "keyword", name = "Object Keyword", type = "string", default = "hazard" },
        { id = "squares", name = "Squares per Round", type = "number", default = 2, min = 1, max = 20 },
        { id = "direction", name = "Direction", type = "choice", default = "east",
            options = {
                { id = "east", text = "East" },
                { id = "west", text = "West" },
                { id = "north", text = "North" },
                { id = "south", text = "South" },
            },
        },
    },

    onRound = function(ctx)
        --the hazard holds position on round 1 and starts advancing on round 2.
        if ctx.round < 2 then
            return
        end
        local keyword = ctx.params.keyword
        if keyword == nil or keyword == "" then
            return
        end
        local tokens = Encounter.GetTargetableObjectsWithKeyword(keyword)
        if #tokens == 0 then
            ctx:Log(string.format("no Targetable objects with keyword \"%s\" on the current map", keyword))
            return
        end

        local dist = ctx.params.squares
        local dx, dy = 0, 0
        if ctx.params.direction == "east" then
            dx = dist
        elseif ctx.params.direction == "west" then
            dx = -dist
        elseif ctx.params.direction == "north" then
            dy = dist
        else
            dy = -dist
        end

        local moved = 0
        for _, token in ipairs(tokens) do
            local inst = token.objectInstance
            if inst ~= nil then
                --stamp the move origin on the Targetable first so remote
                --clients animate the slide, then move the object itself.
                local targetable = inst:GetComponent("Targetable")
                if targetable ~= nil then
                    targetable:SetAndUploadProperties{
                        moveid = dmhub.GenerateGuid(),
                        xorigin = inst.x,
                        yorigin = inst.y,
                        speed = 3,
                    }
                end
                inst:SetAndUploadPos(inst.x + dx, inst.y + dy)
                moved = moved + 1
            end
        end

        if moved > 0 then
            ctx:Announce(string.format("The hazard advances %d squares!", dist))
        end
    end,
}
]==],
}

EncounterScript.RegisterBuiltin{
    id = "builtin:ambush-zone",
    name = "Ambush Zone",
    description = "When a hero moves within the trigger radius of a Targetable map object with the chosen keyword, a reinforcement wave deploys.",
    code = [==[
return {
    name = "Ambush Zone",
    description = "When a hero moves within the trigger radius of a Targetable map object with the chosen keyword, a reinforcement wave deploys. Place a Targetable object (it can be invisible to players) as the zone marker.",

    params = {
        { id = "keyword", name = "Zone Marker Keyword", type = "string", default = "ambush" },
        { id = "radius", name = "Trigger Radius (squares)", type = "number", default = 3, min = 0, max = 30 },
        { id = "wave", name = "Wave to Deploy", type = "wave" },
    },

    think = function(ctx)
        if ctx.state.triggered then
            return
        end

        if ctx.params.wave == nil or ctx.params.wave == "" then
            if not ctx.state.warnedNoWave then
                ctx.state.warnedNoWave = true
                ctx:Log("no wave chosen in the encounter builder; nothing to deploy")
            end
            return
        end

        local markers = Encounter.GetTargetableObjectsWithKeyword(ctx.params.keyword)
        if #markers == 0 then
            return
        end

        for _, token in ipairs(dmhub.allTokens) do
            local isHero = false
            pcall(function()
                isHero = token.properties ~= nil and token.properties:IsHero()
            end)
            if isHero then
                for _, marker in ipairs(markers) do
                    local sameFloor = true
                    pcall(function()
                        sameFloor = (token.floorid == marker.floorid)
                    end)
                    local a = token.loc
                    local b = marker.loc
                    if sameFloor and a ~= nil and b ~= nil then
                        local dist = math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
                        if dist <= ctx.params.radius then
                            ctx.state.triggered = true
                            ctx:Announce("Ambush! Reinforcements pour in!")
                            ctx:DeployWave(ctx.params.wave)
                            return
                        end
                    end
                end
            end
        end
    end,
}
]==],
}
