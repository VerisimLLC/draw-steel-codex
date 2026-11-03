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
    --game-wide, so every client resets hero tokens to the same party size.
    storage = "game",
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

--The party encounters are balanced against is worked out from the player
--party until the Director overrides it in the encounter builder; from then on
--these hold the override (with numheroes as the hero count). No editor: the
--builder's party bar is their only UI.
local g_partyManualSetting = setting {
    id = "encounterpartymanual",
    storage = "game",
    default = false,
}

local g_partyLevelSetting = setting {
    id = "encounterpartylevel",
    storage = "game",
    default = 1,
}

local g_partyVictoriesSetting = setting {
    id = "encounterpartyvictories",
    storage = "game",
    default = 0,
}

--- @class Encounter: GameType
--- @field new fun(o?: table): Encounter
--- @field id string Key of this row in its data table; SetAndUploadTableItem sets it.
Encounter = RegisterGameType('Encounter')

Encounter.name = 'New Encounter'

--Optional free-text notes about the encounter, edited in the encounter builder.
Encounter.description = ''

Encounter.tableName = 'encounters'

--The id of the map in this game the encounter takes place on, or "" when
--none is chosen. Set in the encounter builder; a record, nothing enforces it.
Encounter.mapid = ''

--A Map Library (map pack) map the encounter is set on, as
--"pack|<pack>|<map id>|<name>" (CustomDocument.LibraryMapValue), or "".
--Shipped encounters use it: their mapid and staging name the pack map's id,
--which a game only has once the map is added (Encounter.ResolveMapRef).
Encounter.mapRef = ''

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
        --the book's usual ending: minions left standing flee once the rest fall.
        { id = "nonminions_defeated", text = "All Non-Minions Defeated" },
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

--- The map water level (WATER_LEVEL_REFERENCE.md), for encounter and map scripts:
--- ground lower than the level by 1 square or more is deep water (creatures float
--- on it and can dive), by less is shallow water (difficult terrain without a swim
--- speed). The engine moves creatures with the water and draws it. Sets the current
--- map's level (a multiple of 0.5; nil removes the water). options.floor picks the
--- floor. Runs with host rights, so a directorless game's player host can use it.
--- Returns true, or false and a reason.
--- @param level number|nil
--- @param options nil|{floor: nil|string}
--- @return boolean, string|nil
function Encounter.SetWaterLevel(level, options)
    local map = game.currentMap
    if map == nil then
        return false, "no current map"
    end

    local elevate = rawget(_G, "ElevateToHostPermissions")
    local drop = rawget(_G, "DropHostPermissions")
    if elevate ~= nil then
        elevate()
    end
    local ok, err = pcall(function()
        map:SetWaterLevel(level, options)
    end)
    if drop ~= nil then
        drop()
    end
    if not ok then
        return false, tostring(err)
    end
    return true
end

--- The current map's water level in squares, or nil when it has none.
--- @return number|nil
function Encounter.GetWaterLevel()
    local map = game.currentMap
    if map == nil then
        return nil
    end
    return map:GetWaterLevel()
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
            if monster ~= nil and (mainmonster == nil or monster.properties:EV() > mainmonster.properties:EV()) then
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
            --a damaged group can lose its roster. Treat it as empty so one bad
            --group can't blank the whole journal page (Q3R5F6UY).
            group.monsters = group.monsters or {}

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
        for monsterid, quantity in pairs(group.monsters or {}) do
            local monster = assets.monsters[monsterid]

            if monster ~= nil then
                local entryEV = monster.properties:EV() * quantity
                if monster.properties.minion then
                    entryEV = round(entryEV / 4)
                end

                EDSTotal = EDSTotal + entryEV
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

--The party worked out from the heroes in the game's player party, wherever
--they are: { numHeroes =, level =, victories = } with level and victories
--averaged. numHeroes is held to the party sizes encounters balance for.
--An empty player party gives four level 1 heroes with no victories.
function Encounter.AutoParty()
    local totalLevel = 0
    local totalVictories = 0
    local count = 0
    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(GetDefaultPartyID()) or {}) do
        local tok = dmhub.GetCharacterById(charid)
        local props = tok ~= nil and tok.properties or nil
        if props ~= nil and props:IsHero() then
            count = count + 1
            totalLevel = totalLevel + props:CharacterLevel()
            totalVictories = totalVictories + props:GetVictories()
        end
    end

    if count == 0 then
        return { numHeroes = 4, level = 1, victories = 0 }
    end

    local minHeroes = Encounter.RebalanceHeroCounts[1]
    local maxHeroes = Encounter.RebalanceHeroCounts[#Encounter.RebalanceHeroCounts]
    return {
        numHeroes = math.max(minHeroes, math.min(maxHeroes, count)),
        level = math.max(1, round(totalLevel / count)),
        victories = math.max(0, round(totalVictories / count)),
    }
end

--The party encounters are balanced against, as the builder's party bar holds
--it: { numHeroes =, level =, victories =, manual = }. Auto-calculated from the
--player party unless the Director has overridden it (manual = true).
function Encounter.CurrentParty()
    if g_partyManualSetting:Get() then
        return {
            numHeroes = g_numHeroesSetting:Get(),
            level = g_partyLevelSetting:Get(),
            victories = g_partyVictoriesSetting:Get(),
            manual = true,
        }
    end

    local party = Encounter.AutoParty()
    party.manual = false
    return party
end

--Placement, reinforcements and journal rosters all read the hero count from
--numheroes, so while the party is auto-calculated that setting has to follow
--the player party. Director only: game settings are not writable by players.
local function SyncPartySizeToPlayerParty()
    local party = Encounter.AutoParty()
    if party.numHeroes ~= g_numHeroesSetting:Get() then
        g_numHeroesSetting:Set(party.numHeroes)
    end
end

function Encounter.SyncAutoPartySize()
    if not g_partyManualSetting:Get() then
        SyncPartySizeToPlayerParty()
    end
end

--Save the Director's override of the party; it stops auto-calculating.
function Encounter.SetManualParty(party)
    if g_numHeroesSetting:Get() ~= party.numHeroes then
        g_numHeroesSetting:Set(party.numHeroes)
    end
    if g_partyLevelSetting:Get() ~= party.level then
        g_partyLevelSetting:Set(party.level)
    end
    if g_partyVictoriesSetting:Get() ~= party.victories then
        g_partyVictoriesSetting:Set(party.victories)
    end
    if not g_partyManualSetting:Get() then
        g_partyManualSetting:Set(true)
    end
end

--Drop the Director's override and go back to the auto-calculated party,
--which is returned.
function Encounter.ClearManualParty()
    if g_partyManualSetting:Get() then
        g_partyManualSetting:Set(false)
    end
    SyncPartySizeToPlayerParty()
    return Encounter.AutoParty()
end

--Compute a party's encounter strength from a list of hero/ally tokens.
--
--Hero-side tokens that are NOT monsters (heroes and hero-like allies, e.g. NPCs
--built on a character sheet) each contribute 4 + 2 x their level, and Victories
--are averaged across just those tokens.
--
--Hero-side MONSTER tokens (allied creatures, companions, retainers) are NOT
--heroes and are not worth 4 + 2 x cr; they are counted exactly the way the
--monster side is counted -- by EV, with minions worth 1/minionsPerSquad of a
--squad's EV. This is the same rule as the monster-selection EV chip in
--MCDMCharacterPanel.lua, so an allied monster reads the same whichever side of
--the fight it is on.
--
--Returns nil when the list is empty; otherwise a strength table as in
--PartyStrength, plus:
--  numTokens        : how many tokens contributed (heroes + allies of all kinds)
--  numHeroTokens    : how many non-monster tokens fed the hero-strength maths
--  averageVictories : the averaged Victories used for the bonus
--  minLevel/maxLevel: the level range across the non-monster tokens (nil if none)
--  allyEV           : the EV total of the allied monster tokens
--  numAllyMonsters  : how many allied monster tokens contributed that EV
function Encounter.PartyStrengthFromTokens(tokens)
    local base = 0
    local numHeroTokens = 0
    local totalVictories = 0
    local numHeroes = 0
    local minLevel = nil
    local maxLevel = nil
    local allyEV = 0
    local numAllyMonsters = 0
    for _, tok in ipairs(tokens or {}) do
        if tok.properties:IsMonster() then
            if tok.properties.minion then
                allyEV = allyEV + tok.properties:EV()/GameSystem.minionsPerSquad
            else
                allyEV = allyEV + tok.properties:EV()
            end
            numAllyMonsters = numAllyMonsters + 1
        else
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
            numHeroTokens = numHeroTokens + 1
        end
    end

    if numHeroTokens == 0 and numAllyMonsters == 0 then
        return nil
    end

    allyEV = round(allyEV)

    --A pool of nothing but allied monsters has no hero to average, so the
    --victories bonus is simply zero rather than a divide by zero.
    local averageVictories = 0
    local singleHero = 0
    if numHeroTokens > 0 then
        averageVictories = math.floor(totalVictories / numHeroTokens)
        singleHero = math.floor(base / numHeroTokens)
    end
    local victoryHeroes = math.floor(averageVictories / 2)
    local victoryBonus = math.floor(victoryHeroes * singleHero)
    return {
        total = base + victoryBonus + allyEV,
        base = base,
        singleHero = singleHero,
        victoryBonus = victoryBonus,
        victoryHeroes = victoryHeroes,
        numHeroes = numHeroes,
        numTokens = numHeroTokens + numAllyMonsters,
        numHeroTokens = numHeroTokens,
        allyEV = allyEV,
        numAllyMonsters = numAllyMonsters,
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

-- ===========================================================================
-- Rebalancing an encounter across party sizes
--
-- The builder's "Balance" button. The roster the author built for the current
-- party size is taken as ground truth and left untouched; every other party
-- size 3..7 gets its per-size configuration (group.minHeroes,
-- group.monsterMinHeroes and group.balancing[n].monsters, plus brand-new
-- gated groups) rewritten so the encounter lands at the same point on the
-- difficulty scale.
--
-- "The same difficulty" is defined by the tier maths above: every tier
-- boundary is the party's total strength plus a fixed number of single-hero
-- strengths, and each extra hero adds exactly one single-hero strength to the
-- total. So the encounter reads the same for n heroes when its EV differs
-- from the current EV by (n - n0) single-hero strengths: the surplus above or
-- deficit below the budget, measured in heroes, is preserved.
--
-- The sizes are derived incrementally, stepping away from the current size
-- in both directions: 5 -> 4 -> 3 and 5 -> 6 -> 7. Each step starts from its
-- neighbour's roster and has a budget of one hero's strength (plus whatever
-- the previous step over- or under-shot by), so every larger party is the
-- smaller party's roster plus one more group, and vice versa.
--
-- Units are a squad of minions (group.squadSize, default 4) or one
-- non-minion monster. Stepping UP (adding a hero):
--   1. open exactly one new group, seeded with the least-represented
--      non-minion type whose EV fits the budget. Leaders and Solos are never
--      duplicated. A minion squad may only start a group when the encounter
--      already has a group made purely of minions.
--   2. still within budget, give the new group a minion squad if some
--      existing group pairs that minion with this monster type, then a
--      second monster of the same type.
--   3. spend what is left on existing groups: another squad for a group
--      that already has one, in preference to a duplicate of a monster the
--      group already has; highest letter first within each. No group is
--      given more than two non-minion monsters.
-- Stepping DOWN (removing a hero):
--   1. remove the last group. If that lands more than a hero's strength
--      under target, remove instead whichever group lands closest. A group
--      that is the encounter's only source of a type keeps one unit of it.
--   2. if still over target, remove duplicates (a second copy of a type in a
--      group, or a second squad), highest letter first, while that lands
--      closer to target.
-- ===========================================================================

Encounter.RebalanceHeroCounts = { 3, 4, 5, 6, 7 }

--EV of `quantity` of one monster type, using the CountEDS minion rule.
local function RebalanceEntryEV(props, quantity)
    local ev = props:EV() * quantity
    if props.minion then
        ev = round(ev / 4)
    end
    return ev
end

--Number of units a count of one type represents (squads for minions).
local function RebalanceUnits(count, step)
    return math.ceil(count / step)
end

--Smallest n (3..7) from which `activeByN[n]` is true for every larger n, or
--false when the set is not of that shape, or nil when never active.
local function RebalanceThreshold(activeByN)
    local first = nil
    for _, n in ipairs(Encounter.RebalanceHeroCounts) do
        if activeByN[n] then
            if first == nil then
                first = n
            end
        elseif first ~= nil then
            return false
        end
    end
    return first
end

--Rebalance the encounter for every party size other than party.numHeroes.
--party = { numHeroes =, level =, victories = } as the builder's party bar
--holds it. Mutates self.groups in place (existing group tables are kept so
--open group cards stay valid) and appends any new groups. Returns a summary
--keyed by hero count: { target = EV aimed for, ev = EV achieved, groups =
--number of active groups, added = number of new groups created }.
function Encounter.Rebalance(self, party)
    local n0 = party.numHeroes
    local strength = Encounter.PartyStrength {
        numHeroes = n0,
        level = party.level,
        victories = party.victories,
    }
    local single = strength.singleHero
    local minN = Encounter.RebalanceHeroCounts[1]
    local maxN = Encounter.RebalanceHeroCounts[#Encounter.RebalanceHeroCounts]

    --------------------------------------------------------------------------
    -- Gather the working model: one "slot" per group that holds at least one
    -- known monster type. Groups the model skips are left exactly as they are.
    --------------------------------------------------------------------------
    local infoCache = {}
    local function Info(monsterid)
        local info = infoCache[monsterid]
        if info == nil then
            local asset = assets.monsters[monsterid]
            if asset == nil then
                info = false
            else
                local props = asset.properties
                local org = OrganizationKeyword(props)
                info = {
                    props = props,
                    minion = props.minion and true or false,
                    boss = (org == "leader" or org == "solo"),
                    unitEV = RebalanceEntryEV(props, cond(props.minion, 4, 1)),
                }
            end
            infoCache[monsterid] = info
        end
        return info or nil
    end

    local slots = {}
    for groupIndex, group in ipairs(self.groups) do
        local types = {}
        for monsterid, _ in pairs(group.monsters or {}) do
            if Info(monsterid) ~= nil then
                types[#types + 1] = monsterid
            end
        end
        if #types > 0 then
            table.sort(types)
            local slot = {
                group = group,
                index = groupIndex,
                types = types,
                step = {},
                base0 = {},
            }
            for _, monsterid in ipairs(types) do
                slot.step[monsterid] = cond(Info(monsterid).minion, group.squadSize or 4, 1)
                --AdjustedMonsterQuantity applies the per-monster gate; the
                --group gate is the caller's job, as in AdjustedGroupEV.
                if group.minHeroes ~= nil and group.minHeroes > n0 then
                    slot.base0[monsterid] = 0
                else
                    slot.base0[monsterid] = Encounter.AdjustedMonsterQuantity(group, monsterid, group.monsters[monsterid] or 0, n0)
                end
            end
            slots[#slots + 1] = slot
        end
    end

    --the set of types the encounter uses anywhere; the only types allowed in.
    local allTypes = {}
    local allTypesList = {}
    for _, slot in ipairs(slots) do
        for _, monsterid in ipairs(slot.types) do
            if not allTypes[monsterid] then
                allTypes[monsterid] = true
                allTypesList[#allTypesList + 1] = monsterid
            end
        end
    end
    table.sort(allTypesList)

    --counts[n][slotIndex][monsterid] = number of that monster placed at n heroes.
    local counts = {}
    counts[n0] = {}
    for s, slot in ipairs(slots) do
        counts[n0][s] = {}
        for _, monsterid in ipairs(slot.types) do
            counts[n0][s][monsterid] = slot.base0[monsterid]
        end
    end

    --------------------------------------------------------------------------
    -- Helpers over a roster.
    --------------------------------------------------------------------------
    local function Count(roster, s, monsterid)
        return (roster[s] and roster[s][monsterid]) or 0
    end

    local function GroupEV(roster, s)
        local total = 0
        for _, monsterid in ipairs(slots[s].types) do
            local c = Count(roster, s, monsterid)
            if c > 0 then
                total = total + RebalanceEntryEV(Info(monsterid).props, c)
            end
        end
        return total
    end

    local function RosterEV(roster)
        local total = 0
        for s = 1, #slots do
            total = total + GroupEV(roster, s)
        end
        return total
    end

    local function GroupActive(roster, s)
        for _, monsterid in ipairs(slots[s].types) do
            if Count(roster, s, monsterid) > 0 then
                return true
            end
        end
        return false
    end

    local function ActiveGroupCount(roster)
        local n = 0
        for s = 1, #slots do
            if GroupActive(roster, s) then
                n = n + 1
            end
        end
        return n
    end

    --units of a type across the whole roster.
    local function TypeUnits(roster, monsterid)
        local n = 0
        for s, slot in ipairs(slots) do
            local c = Count(roster, s, monsterid)
            if c > 0 then
                n = n + RebalanceUnits(c, slot.step[monsterid])
            end
        end
        return n
    end

    --non-minion monsters in a group.
    local function GroupNonMinions(roster, s)
        local n = 0
        for _, monsterid in ipairs(slots[s].types) do
            if not Info(monsterid).minion then
                n = n + Count(roster, s, monsterid)
            end
        end
        return n
    end

    --a group made purely of minions exists somewhere in the roster.
    local function HasPureMinionGroup(roster)
        for s = 1, #slots do
            if GroupActive(roster, s) and GroupNonMinions(roster, s) == 0 then
                return true
            end
        end
        return false
    end

    --a minion type that shares a group with the given monster type somewhere
    --in the roster, or nil.
    local function PairedMinion(roster, monsterid)
        for s, slot in ipairs(slots) do
            if Count(roster, s, monsterid) > 0 then
                for _, other in ipairs(slot.types) do
                    if Info(other).minion and Count(roster, s, other) > 0 then
                        return other
                    end
                end
            end
        end
        return nil
    end

    --EV change from adding one unit of a type to a slot.
    local function AddDelta(roster, s, monsterid)
        local props = Info(monsterid).props
        local c = Count(roster, s, monsterid)
        local step = slots[s].step[monsterid] or cond(Info(monsterid).minion, 4, 1)
        return RebalanceEntryEV(props, c + step) - RebalanceEntryEV(props, c), step
    end

    --EV change (positive) from removing one unit of a type from a slot, and
    --the number of monsters that removal takes away.
    local function RemoveDelta(roster, s, monsterid)
        local props = Info(monsterid).props
        local c = Count(roster, s, monsterid)
        local take = math.min(c, slots[s].step[monsterid])
        return RebalanceEntryEV(props, c) - RebalanceEntryEV(props, c - take), take
    end

    --add one unit of a type to a slot, registering the type on the slot if
    --it is new there. Returns the EV added.
    local function AddUnit(roster, s, monsterid)
        local slot = slots[s]
        if slot.step[monsterid] == nil then
            slot.types[#slot.types + 1] = monsterid
            table.sort(slot.types)
            if Info(monsterid).minion then
                slot.step[monsterid] = (slot.group and slot.group.squadSize) or 4
            else
                slot.step[monsterid] = 1
            end
            slot.base0[monsterid] = 0
            for _, r in pairs(counts) do
                if r[s] ~= nil and r[s][monsterid] == nil then
                    r[s][monsterid] = 0
                end
            end
        end
        local delta, step = AddDelta(roster, s, monsterid)
        roster[s][monsterid] = Count(roster, s, monsterid) + step
        return delta
    end

    local function CopyRoster(roster)
        local copy = {}
        for s = 1, #slots do
            copy[s] = {}
            for monsterid, c in pairs(roster[s] or {}) do
                copy[s][monsterid] = c
            end
        end
        return copy
    end

    --pick the winner among candidates by an ordered list of scores (higher
    --wins at every position); ties fall to the earlier candidate.
    local function Best(candidates)
        local best = nil
        for _, cand in ipairs(candidates) do
            if best == nil then
                best = cand
            else
                for i = 1, #cand.score do
                    if cand.score[i] > best.score[i] then
                        best = cand
                        break
                    elseif cand.score[i] < best.score[i] then
                        break
                    end
                end
            end
        end
        return best
    end

    --------------------------------------------------------------------------
    -- Stepping up: derive the roster for one more hero.
    --------------------------------------------------------------------------
    local function OpenGroup()
        local slot = {
            group = nil,
            index = #slots + 1,
            types = {},
            step = {},
            base0 = {},
        }
        slots[#slots + 1] = slot
        for _, r in pairs(counts) do
            r[#slots] = r[#slots] or {}
        end
        return #slots
    end

    local function StepUp(roster, budget)
        local added = 0

        --1. the new group's first monster: least-represented type that fits.
        local allowMinionStart = HasPureMinionGroup(roster)
        local candidates = {}
        for _, monsterid in ipairs(allTypesList) do
            local info = Info(monsterid)
            --allTypesList only holds ids whose Info() was non-nil (and cached) when the slots were built.
            ---@cast info -nil
            if not info.boss and (allowMinionStart or not info.minion) and info.unitEV <= budget then
                candidates[#candidates + 1] = {
                    monsterid = monsterid,
                    score = { -TypeUnits(roster, monsterid), cond(info.minion, 0, 1), -info.unitEV },
                }
            end
        end
        local first = Best(candidates)
        if first ~= nil then
            local s = OpenGroup()
            added = 1
            budget = budget - AddUnit(roster, s, first.monsterid)

            --2. a paired minion squad, then a second of the same monster.
            local info = Info(first.monsterid)
            --first.monsterid came from allTypesList, whose Info() is non-nil and cached.
            ---@cast info -nil
            if not info.minion then
                local minion = PairedMinion(roster, first.monsterid)
                if minion ~= nil then
                    local squad = Info(minion).unitEV
                    if squad <= budget then
                        budget = budget - AddUnit(roster, s, minion)
                    end
                end
                local delta = AddDelta(roster, s, first.monsterid)
                if delta <= budget then
                    budget = budget - AddUnit(roster, s, first.monsterid)
                end
            end
        end

        --3. spend the rest on existing groups: squads before duplicate
        --monsters, highest letter first.
        while true do
            local options = {}
            for s, slot in ipairs(slots) do
                if GroupActive(roster, s) then
                    local nonMinions = GroupNonMinions(roster, s)
                    for _, monsterid in ipairs(slot.types) do
                        local info = Info(monsterid)
                        --slot.types only holds ids whose Info() was non-nil (and cached).
                        ---@cast info -nil
                        if Count(roster, s, monsterid) > 0 and not info.boss
                            and (info.minion or nonMinions < 2) then
                            local delta = AddDelta(roster, s, monsterid)
                            if delta > 0 and delta <= budget then
                                options[#options + 1] = {
                                    s = s,
                                    monsterid = monsterid,
                                    score = { cond(info.minion, 1, 0), s, -TypeUnits(roster, monsterid), -delta },
                                }
                            end
                        end
                    end
                end
            end
            local pick = Best(options)
            if pick == nil then
                break
            end
            budget = budget - AddUnit(roster, pick.s, pick.monsterid)
        end

        return added
    end

    --------------------------------------------------------------------------
    -- Stepping down: derive the roster for one fewer hero.
    --------------------------------------------------------------------------

    --what removing a group leaves behind: one unit of any type the group is
    --the encounter's only source of. Returns the EV removed and the remains.
    local function GroupRemoval(roster, s)
        local keep = {}
        local removedEV = 0
        for _, monsterid in ipairs(slots[s].types) do
            local c = Count(roster, s, monsterid)
            if c > 0 then
                local step = slots[s].step[monsterid]
                local remain = 0
                if TypeUnits(roster, monsterid) - RebalanceUnits(c, step) == 0 then
                    remain = math.min(c, step)
                end
                keep[monsterid] = remain
                local props = Info(monsterid).props
                removedEV = removedEV + RebalanceEntryEV(props, c) - RebalanceEntryEV(props, remain)
            end
        end
        return removedEV, keep
    end

    local function StepDown(roster, target)
        local ev = RosterEV(roster)

        --1. remove a group: the last one, unless that lands more than a
        --hero's strength under target, in which case whichever lands closest.
        local active = {}
        for s = 1, #slots do
            if GroupActive(roster, s) then
                active[#active + 1] = s
            end
        end
        if #active >= 2 then
            local choice = nil
            local last = active[#active]
            local lastEV = GroupRemoval(roster, last)
            if lastEV > 0 and ev - lastEV >= target - single then
                choice = last
            else
                local bestDistance = nil
                for i = #active, 1, -1 do
                    local s = active[i]
                    local removedEV = GroupRemoval(roster, s)
                    if removedEV > 0 then
                        local distance = math.abs(ev - removedEV - target)
                        if bestDistance == nil or distance < bestDistance then
                            bestDistance = distance
                            choice = s
                        end
                    end
                end
            end
            if choice ~= nil then
                local removedEV, keep = GroupRemoval(roster, choice)
                for monsterid, remain in pairs(keep) do
                    roster[choice][monsterid] = remain
                end
                ev = ev - removedEV
            end
        end

        --2. still over: remove duplicates, highest letter first, while that
        --lands closer.
        while ev > target do
            local options = {}
            for s, slot in ipairs(slots) do
                if GroupActive(roster, s) then
                    for _, monsterid in ipairs(slot.types) do
                        local c = Count(roster, s, monsterid)
                        if RebalanceUnits(c, slot.step[monsterid]) >= 2 then
                            local delta, take = RemoveDelta(roster, s, monsterid)
                            if delta > 0 and math.abs(ev - delta - target) < math.abs(ev - target) then
                                options[#options + 1] = {
                                    s = s,
                                    monsterid = monsterid,
                                    delta = delta,
                                    take = take,
                                    score = { s, TypeUnits(roster, monsterid), -delta },
                                }
                            end
                        end
                    end
                end
            end
            local pick = Best(options)
            if pick == nil then
                break
            end
            roster[pick.s][pick.monsterid] = roster[pick.s][pick.monsterid] - pick.take
            ev = ev - pick.delta
        end
    end

    --------------------------------------------------------------------------
    -- Walk out from the current size in both directions.
    --------------------------------------------------------------------------
    local ev0 = RosterEV(counts[n0])
    local summary = {}
    summary[n0] = { target = ev0, ev = ev0, groups = ActiveGroupCount(counts[n0]), added = 0 }

    for n = n0 + 1, maxN do
        local roster = CopyRoster(counts[n - 1])
        counts[n] = roster
        local target = ev0 + (n - n0) * single
        local added = StepUp(roster, target - RosterEV(roster))
        summary[n] = { target = target, ev = RosterEV(roster), groups = ActiveGroupCount(roster), added = added }
    end

    for n = n0 - 1, minN, -1 do
        local roster = CopyRoster(counts[n + 1])
        counts[n] = roster
        local target = ev0 + (n - n0) * single
        StepDown(roster, target)
        summary[n] = { target = target, ev = RosterEV(roster), groups = ActiveGroupCount(roster), added = 0 }
    end

    --------------------------------------------------------------------------
    -- Write the rosters back as base quantities + gates + balancing deltas.
    -- The base quantity of each entry is its count at the smallest party size
    -- it appears for; everything else is a delta from that, so
    -- AdjustedMonsterQuantity reproduces the rosters exactly.
    --------------------------------------------------------------------------
    for s, slot in ipairs(slots) do
        local group = slot.group
        if group == nil then
            group = { monsters = {} }
            self.groups[#self.groups + 1] = group
            slot.group = group
        end

        --group gate: the smallest party size the group is active for, when the
        --active sizes form a "n and up" run; otherwise no gate (the deltas
        --zero the group out where it is inactive).
        local activeByN = {}
        for _, n in ipairs(Encounter.RebalanceHeroCounts) do
            activeByN[n] = GroupActive(counts[n], s)
        end
        local threshold = RebalanceThreshold(activeByN)
        if threshold == nil then
            --never active at any size: an author-made group gated above the
            --current size that the walk never opened. Its gate is kept and
            --the per-entry deltas below zero it out wherever the gate would
            --have let it in, so the rosters stay exactly what the walk built.
        elseif threshold == false or threshold == minN then
            group.minHeroes = nil
        else
            group.minHeroes = threshold
        end

        --balancing is keyed by hero count and must stay dense from 1 (see
        --ShowBalancingPopup in EncounterPanel.lua); keep stamina/disableSolo.
        local balancing = group.balancing or {}
        for i = 1, 7 do
            balancing[i] = balancing[i] or {}
            balancing[i].monsters = {}
        end

        local monsterMinHeroes = {}
        for _, monsterid in ipairs(slot.types) do
            local presentByN = {}
            local baseN = nil
            for _, n in ipairs(Encounter.RebalanceHeroCounts) do
                local c = Count(counts[n], s, monsterid)
                presentByN[n] = c > 0
                if c > 0 and baseN == nil then
                    baseN = n
                end
            end

            if baseN == nil then
                --never placed at any size: keep the author's base quantity and
                --zero it out of every size the algorithm covers.
                if (group.monsters[monsterid] or 0) > 0 then
                    for _, n in ipairs(Encounter.RebalanceHeroCounts) do
                        balancing[n].monsters[monsterid] = -group.monsters[monsterid]
                    end
                end
            else
                local base = Count(counts[baseN], s, monsterid)
                group.monsters[monsterid] = base
                local entryThreshold = RebalanceThreshold(presentByN)
                if entryThreshold ~= false and entryThreshold ~= minN then
                    monsterMinHeroes[monsterid] = entryThreshold
                end
                for _, n in ipairs(Encounter.RebalanceHeroCounts) do
                    local c = Count(counts[n], s, monsterid)
                    local gatedOut = (group.minHeroes ~= nil and n < group.minHeroes)
                        or (monsterMinHeroes[monsterid] ~= nil and n < monsterMinHeroes[monsterid])
                    if not gatedOut and c ~= base then
                        balancing[n].monsters[monsterid] = c - base
                    end
                end
            end
        end

        --entries the model skipped (unknown assets) keep any gate they had.
        for monsterid, gate in pairs(group.monsterMinHeroes or {}) do
            if not allTypes[monsterid] then
                monsterMinHeroes[monsterid] = gate
            end
        end
        if next(monsterMinHeroes) == nil then
            group.monsterMinHeroes = nil
        else
            group.monsterMinHeroes = monsterMinHeroes
        end
        group.balancing = balancing
    end

    return summary
end

--Count the non-minion monsters across the WHOLE encounter (start groups + every
--reinforcement wave) at the given hero count. Uses CloneForNumberOfHeroes so the
--count reflects what actually spawns (minHeroes filtering + per-hero balancing).
--Minions are left out.
-- Counts the non-minion monsters in the encounter for a given number of heroes
-- (including reinforcement waves). If org is given (a lowercase organization keyword
-- such as "leader"), only monsters of that organization are counted.
function Encounter.CountNonMinionMonsters(self, numHeroes, org)
    local clone = self:CloneForNumberOfHeroes(numHeroes)
    local count = 0
    for _, group in ipairs(clone.groups) do
        for monsterid, quantity in pairs(group.monsters or {}) do
            local monster = assets.monsters[monsterid]
            if monster ~= nil and not monster.properties.minion and
                (org == nil or OrganizationKeyword(monster.properties) == org) then
                count = count + quantity
            end
        end
    end
    return count
end

--How many minion squads this group is placed as. Fewer than 8 minions make one
--squad; 8 or more are split into squads of the group's squad size.
function Encounter.GroupMinionSquadCount(group)
    for monsterid, quantity in pairs(group.monsters or {}) do
        local monster = assets.monsters[monsterid]
        if monster ~= nil and monster.properties.minion and quantity ~= nil and quantity > 0 then
            if quantity >= 8 then
                return math.ceil(quantity / (group.squadSize or 4))
            end
            return 1
        end
    end
    return 0
end

--How many monsters the heroes face, including reinforcements. Each minion squad
--counts as one monster (KFG3P24T).
function Encounter.CountVictoryUnits(self, numHeroes)
    local count = self:CountNonMinionMonsters(numHeroes)
    local clone = self:CloneForNumberOfHeroes(numHeroes)
    for _, group in ipairs(clone.groups) do
        count = count + Encounter.GroupMinionSquadCount(group)
    end
    return count
end

--Which monster this token counts as when checking for victory, or nil if it
--doesn't count. Every minion in a squad returns the same answer, so the squad
--counts once. Summoned minions don't count.
--True for a creature summoned by a hero or a companion, e.g. a Familiar perk's
--stat block. It fights for the heroes, so it is never a monster left to defeat;
--counting one meant an "all defeated" victory never came.
--- @param token CharacterToken
--- @return boolean
function Encounter.IsHeroSideSummon(token)
    local summonerid = token.summonerid
    if summonerid == nil or summonerid == "" then
        return false
    end
    local summoner = dmhub.GetTokenById(summonerid)
    return summoner ~= nil and summoner.valid and summoner.properties ~= nil and not summoner.properties:IsMonster()
end

function Encounter.VictoryUnitKey(token)
    local props = token.properties
    if props == nil or not props:IsMonster() or Encounter.IsHeroSideSummon(token) then
        return nil
    end
    if not props.minion then
        return token.charid
    end
    if token.summonerid ~= nil and token.summonerid ~= "" then
        return nil
    end
    return "squad:" .. tostring(props:MinionSquad())
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

        for monsterid, quantity in pairs(group.monsters or {}) do
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
            for monsterid,quantity in pairs(group.monsters or {}) do
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

-- ===========================================================================
-- Saved mount relationships
--
-- A monster sitting in another monster's saddle -- a goblin riding a wolf, or
-- anything that has climbed a bigger creature -- is part of an encounter's
-- setup just as much as where it stands, so it is banked and restored
-- alongside group.spawnlocs.
--
-- The tokens are deleted and respawned as brand new characters every cycle, so
-- a saved mount cannot name a charid. It names a SLOT: the (group index, spawn
-- slot) pair positions are already keyed by. group.mounts is a dense LIST of
-- records -- never a slot-keyed sparse array, which serialization compacts,
-- shifting every later entry:
--
--   { slot       = the rider's own spawn slot,
--     mountGroup = group index of the creature it is riding,
--     mountSlot  = that creature's spawn slot,
--     saddle     = the saddle index it sat in }
--
-- Only mounts that are part of the same encounter are recorded: a monster
-- riding a hero's horse is left alone, since nothing here respawns that horse.
-- ===========================================================================

-- The mount recorded for one spawn slot, or nil if that slot rides nothing.
function Encounter.GetMountForSlot(self, groupIndex, slot)
    local group = self.groups[groupIndex]
    if group == nil then
        return nil
    end

    for _,entry in ipairs(group.mounts or {}) do
        if entry.slot == slot then
            return entry
        end
    end

    return nil
end

-- Keep saved mounts pointing at the right groups after a group is deleted from
-- the plan: a mount names its group by INDEX, so references to the group that
-- went away are dropped and references past it shift down. Call it immediately
-- after table.remove on encounter.groups.
function Encounter.RepairMountsAfterGroupRemoved(self, removedIndex)
    for _,group in ipairs(self.groups) do
        if group.mounts ~= nil then
            local kept = {}
            for _,entry in ipairs(group.mounts) do
                if entry.mountGroup ~= removedIndex then
                    if entry.mountGroup > removedIndex then
                        entry.mountGroup = entry.mountGroup - 1
                    end
                    kept[#kept+1] = entry
                end
            end
            group.mounts = kept
        end
    end
end

-- Bank the mount relationships among a set of placed tokens, ready for the
-- tokens to be deleted. entries is a list of
--   { group = <group index>, slot = <spawn slot>, token = <CharacterToken> }
-- in the same slot numbering the caller banks positions with. Every group named
-- in entries has its saved mounts REPLACED, so a monster taken off its mount
-- before saving stops being recorded.
function Encounter.RecordMounts(self, entries)
    local entryOfCharid = {}
    local cleared = {}
    for _,entry in ipairs(entries) do
        if not cleared[entry.group] then
            cleared[entry.group] = true
            local group = self.groups[entry.group]
            if group ~= nil then
                group.mounts = {}
            end
        end

        if entry.token ~= nil then
            entryOfCharid[entry.token.charid] = entry
        end
    end

    for _,entry in ipairs(entries) do
        local token = entry.token
        --saddleMount is the creature directly underneath; mount would walk the
        --whole chain to the bottom of a stack of riders.
        local mountToken = token ~= nil and token.saddleMount or nil
        local mountEntry = mountToken ~= nil and entryOfCharid[mountToken.charid] or nil
        local group = self.groups[entry.group]
        if mountEntry ~= nil and group ~= nil then
            group.mounts[#group.mounts+1] = {
                slot = entry.slot,
                mountGroup = mountEntry.group,
                mountSlot = mountEntry.slot,
                --which seat: a mount with several authored saddles (a howdah, a
                --wagon) puts its riders back where the Director sat them.
                saddle = token.mountedSaddle or 0,
            }
        end
    end
end

-- Seat riders back onto their mounts from the encounter's saved mounts. entries
-- is the same shape RecordMounts takes, holding the tokens just spawned. A mount
-- reference naming a slot that is not in entries is skipped -- the creature it
-- rides is not being placed in this pass (a reinforcement riding a monster that
-- was placed up front, say), so there is nothing to seat it on.
--
-- An entry marked mountOnly is a token that is ALREADY on the map: it is offered
-- as something to seat riders on, but is not itself re-seated. That is how a
-- group placed on its own finds a mount belonging to a group placed earlier
-- without disturbing creatures the Director has since moved or dismounted.
function Encounter.RestoreMounts(self, entries)
    --CHARIDS, not the token objects the caller was handed. A token straight out of
    --game.SpawnTokenFromBestiaryLocally is not yet backed by a live map token, and
    --ClimbOntoCreature on one silently returns false (it bails on a null token).
    --Looking the same charid up again with dmhub.GetTokenById gives a wrapper that
    --works right away -- this is what made saved mounts appear to be ignored.
    local charidAtSlot = {}
    for _,entry in ipairs(entries) do
        if entry.token ~= nil then
            charidAtSlot[string.format("%d:%d", entry.group, entry.slot)] = entry.token.charid
        end
    end

    local riders = {}
    for _,entry in ipairs(entries) do
        local mountRef = nil
        if not entry.mountOnly then
            mountRef = self:GetMountForSlot(entry.group, entry.slot)
        end

        local mountCharid = nil
        if mountRef ~= nil then
            mountCharid = charidAtSlot[string.format("%d:%d", mountRef.mountGroup, mountRef.mountSlot)]
        end

        if mountCharid ~= nil and entry.token ~= nil then
            --mountCharid is only set from a non-nil mountRef.
            ---@cast mountRef -nil
            --how deep in a stack of riders this one sits, so a stack is rebuilt
            --from the bottom up rather than in whatever order the groups spawned.
            --The walk is bounded in case saved data ever describes a loop.
            local depth = 0
            local walk = mountRef
            while walk ~= nil and depth < 20 do
                depth = depth + 1
                walk = self:GetMountForSlot(walk.mountGroup, walk.mountSlot)
            end

            riders[#riders+1] = {
                charid = entry.token.charid,
                mountCharid = mountCharid,
                saddle = mountRef.saddle or 0,
                depth = depth,
            }
        end
    end

    if #riders == 0 then
        return
    end

    table.sort(riders, function(a,b) return a.depth < b.depth end)

    --A token that has not resolved yet (the engine's own placement path hands the
    --charids over before they are queryable) is retried for a couple of seconds
    --rather than dropped.
    local attempts = 20
    local function Seat()
        if mod.unloaded then
            return
        end

        local remaining = {}
        for _,rider in ipairs(riders) do
            local riderToken = dmhub.GetTokenById(rider.charid)
            local mountToken = dmhub.GetTokenById(rider.mountCharid)
            local seated = false
            if riderToken ~= nil and mountToken ~= nil then
                seated = riderToken:ClimbOntoCreature(mountToken, rider.saddle)
            end

            if not seated then
                remaining[#remaining+1] = rider
            end
        end

        riders = remaining
        if #riders > 0 and attempts > 0 then
            attempts = attempts - 1
            dmhub.Schedule(0.1, Seat)
        end
    end

    Seat()
end

-- LiveEncounter represents the state of an encounter that is currently running
-- (i.e. that has been pushed live into an initiative queue). It derives from
-- Encounter and begins life as a deep copy of an authored Encounter, re-typed as a
-- LiveEncounter so it is its own distinct type -- it inherits all of Encounter's
-- fields and methods but can carry live-only state and extensions.
--- @class LiveEncounter: Encounter
--- @field new fun(o?: table): LiveEncounter
--- @field id string Key of this row in its data table; SetAndUploadTableItem sets it.
LiveEncounter = RegisterGameType("LiveEncounter", "Encounter")

-- Its own table name so it is distinguished from authored encounters.
LiveEncounter.tableName = "liveencounters"

-- The monster count captured at the onset of combat (start groups + all
-- reinforcement waves), with each minion squad counted as one monster. Used as the
-- denominator for the "Half Monsters Defeated" victory check so it stays stable as
-- monsters die / reinforcements arrive.
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

-- Set true when the director presses "Declare Defeat". The defeat counterpart of
-- victoryAwarded: the same full-screen outcome screen takes over on every client,
-- titled DEFEAT and opening on its Monsters tab. Cleared when combat ends.
LiveEncounter.defeatAwarded = false

-- Set true when the director presses "Award" on the victory screen to grant each hero
-- this encounter's Victories. Networked (rides in the queue) so every client plays the
-- victory-icon drop animation and shows each hero's "Victories: old -> new" change.
LiveEncounter.victoriesAwarded = false

-- A snapshot of the heroes present at the onset of combat, used by the victory screen.
-- A list of { charid, name, recoveries }, where recoveries is how many Recoveries the
-- hero had available when combat began. Populated by RecordOnsetHeroes. Stored as a
-- dense list (not a sparse map) so it survives network serialization unchanged.
LiveEncounter.onsetHeroes = nil

-- A snapshot of the monster-side initiative groupings, used by the victory screen's
-- Monsters tab and by monster stat attribution. A dense list of
-- { groupid, statKey, name, memberids, memberinfo }, where groupid is the group's
-- initiative id (see InitiativeQueue.GetInitiativeId), statKey is its path-safe form
-- used to key monsterStats, memberids are the member tokenids seen when the group
-- entered combat, and memberinfo maps each member tokenid to a small display snapshot
-- ({ minion, portrait, monsterType, role }) so the victory screen can still show the
-- group after its tokens are despawned or deleted (dead monsters leave the map).
-- Populated by RecordOnsetMonsterGroups at combat start and topped up when
-- reinforcements join (Commands.rollinitiative additions, DeployWave).
LiveEncounter.onsetMonsterGroups = nil

-- Server time in milliseconds when combat began. Stamped by the first
-- RecordOnsetHeroes / RecordOnsetMonsterGroups call and never overwritten, so
-- reinforcements topping up the snapshot do not restart the clock. Read by
-- BuildBattleRecord to give each battle log entry a real duration. 0 means
-- unknown (a combat that started before this field existed, or one whose onset
-- was never snapshotted); duration is omitted from the record in that case.
-- dmhub.serverTimeMilliseconds is used rather than ServerTimestamp() because it
-- is a plain number, consistent across clients, and readable immediately without
-- waiting for a server-side placeholder to resolve.
LiveEncounter.onsetTimestamp = 0

-- How many users were connected when combat began (see CountLoggedInUsers).
-- Stamped alongside onsetTimestamp. The battle record keeps this as well as the
-- count at the end of combat, because either one alone undercounts a real
-- session: someone can drop before the director gets round to pressing Proceed,
-- and someone else can join mid-fight. The seriousness check uses the larger of
-- the two. 0 means unknown.
LiveEncounter.onsetUsercount = 0

-- Stamp the combat start time and connected-user count, if not already stamped.
-- Callers network the change afterwards, like every other live-encounter
-- mutation. Never overwrites, so reinforcements topping up the onset snapshot do
-- not restart the clock.
function LiveEncounter:StampOnsetTimestamp()
    if self:try_get("onsetTimestamp", 0) > 0 then
        return
    end
    self.onsetTimestamp = dmhub.serverTimeMilliseconds
    local users = 0
    pcall(function() users = CountLoggedInUsers() end)
    self.onsetUsercount = users
end

-- Construct a LiveEncounter from an authored Encounter. The result is a deep copy
-- of the encounter's data, re-typed as a LiveEncounter: its typeName, metatable,
-- and tableName are updated to LiveEncounter so it serializes and behaves as a
-- LiveEncounter (while still inheriting everything from Encounter).
function LiveEncounter.Create(encounter)
    local result = DeepCopy(encounter)
    result.typeName = "LiveEncounter"
    result.tableName = LiveEncounter.tableName
    setmetatable(result, LiveEncounter.mt)
    --record the full monster count (including reinforcements that will arrive) at
    --the onset of combat. Each minion squad counts as one monster.
    result.onsetMonsterCount = result:CountVictoryUnits()
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
    --for "All Non-Minions Defeated": the progress denominator, and the guard that an
    --encounter with no non-minions falls back to "All Monsters Defeated".
    if result:try_get("victoryCondition") == "nonminions_defeated" then
        result.onsetNonMinionCount = result:CountNonMinionMonsters(nil)
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
    self:StampOnsetTimestamp()
end

-- The onset hero snapshot (see RecordOnsetHeroes); always a list.
function LiveEncounter:GetOnsetHeroes()
    return self:try_get("onsetHeroes") or {}
end

-- Stat ids and the path segments fed to dmhub:IncrementInitiativeData must be
-- path-safe (^[a-zA-Z0-9_\-.:]+$ -- see STATS_TRACKING.md). Initiative group ids
-- can contain spaces (e.g. "MONSTER-Goblin Warrior"), so monsterStats is keyed by
-- this sanitized form of the group id. Deterministic, so attribution and display
-- always agree on the key.
local function SanitizeStatKey(id)
    --capture gsub's first return only, so callers can use this in argument lists
    --without gsub's count leaking as an extra value.
    local result = string.gsub(tostring(id), "[^%w_%-%.:]", "_")
    return result
end

-- Record (or top up) the monster-side initiative groupings entering combat.
-- tokenids is a list of monster tokenids being added to initiative; each token's
-- current initiative id defines its grouping (a minion squad plus its captain, or
-- several monsters deliberately grouped, share one id and so form one group).
-- Upserts into onsetMonsterGroups: new groups are appended (preserving the order
-- they entered combat), new members join their existing group, and nothing is ever
-- removed -- so reinforcements arriving mid-fight extend the snapshot rather than
-- rewriting it. Callers must network the change afterwards (the live encounter
-- rides inside the queue). Never throws.
function LiveEncounter:RecordOnsetMonsterGroups(tokenids)
    local ok, err = pcall(function()
        local groups = {}
        local index = {}
        for _, g in ipairs(self:GetOnsetMonsterGroups()) do
            groups[#groups+1] = g
            index[g.groupid] = g
        end

        for _, tokenid in ipairs(tokenids or {}) do
            local token = dmhub.GetTokenById(tokenid)
            if token ~= nil and token.properties ~= nil and not token.properties:IsHero() then
                local groupid = InitiativeQueue.GetInitiativeId(token)
                if groupid ~= nil then
                    local g = index[groupid]
                    if g == nil then
                        g = {
                            groupid = groupid,
                            statKey = SanitizeStatKey(groupid),
                            name = token.description,
                            memberids = {},
                        }
                        groups[#groups+1] = g
                        index[groupid] = g
                    end
                    local present = false
                    for _, mid in ipairs(g.memberids) do
                        if mid == tokenid then
                            present = true
                            break
                        end
                    end
                    if not present then
                        g.memberids[#g.memberids+1] = tokenid
                    end

                    --Display snapshot for this member, so the victory screen can
                    --still show the group after its token despawns or is deleted
                    --(dead monsters leave the map). portrait is omitted for
                    --spine-animated tokens: their inspect portrait is a live
                    --spine render that cannot outlive the token.
                    if g.memberinfo == nil then
                        g.memberinfo = {}
                    end
                    if g.memberinfo[tokenid] == nil then
                        local info = {
                            minion = token.properties:try_get("minion", false) == true,
                        }
                        if not token.hasSpineAnimation then
                            info.portrait = token.inspectPortrait
                        end
                        local mtype = token.properties:try_get("monster_type")
                        if mtype ~= nil and mtype ~= "" then
                            info.monsterType = mtype
                        end
                        local mrole = token.properties:try_get("role")
                        if mrole ~= nil and mrole ~= "" then
                            info.role = mrole
                        end
                        g.memberinfo[tokenid] = info
                    end
                end
            end
        end

        self.onsetMonsterGroups = groups
        self:StampOnsetTimestamp()
    end)

    if not ok then
        dmhub.Debug(string.format("LiveEncounter.RecordOnsetMonsterGroups: failed: %s", tostring(err)))
    end
end

-- The onset monster-group snapshot (see RecordOnsetMonsterGroups); always a list.
function LiveEncounter:GetOnsetMonsterGroups()
    return self:try_get("onsetMonsterGroups") or {}
end

-- The monster groupings to display for this encounter: the onset snapshot (in the
-- order the groups entered combat) merged with any non-player initiative entries
-- that were never snapshotted (e.g. monsters added to initiative through a path
-- that predates the snapshot). Each result entry is:
--   {
--     groupid,      -- the initiative id
--     statKey,      -- key into monsterStats (sanitized groupid)
--     name,         -- display name for the group
--     tokens,       -- member tokens still resolvable on the map, heroes excluded
--     memberCount,  -- #tokens plus onset members whose tokens are gone
--     aliveCount, deadCount, allDead,
--     primaryToken, -- the token to show as the group's portrait (captain preferred);
--                   -- may be an off-map token for a dead member, or nil when every
--                   -- member's token has been deleted outright
--     fallbackInfo, -- onset display snapshot ({ minion, portrait, monsterType, role })
--                   -- to draw the card from when primaryToken is nil; may be nil
--   }
-- Onset members whose tokens no longer resolve on the map (dead monsters are
-- despawned or deleted) still count as dead members, so the victory screen shows
-- the full roster rather than just the survivors. Groups with no resolvable
-- members and no onset members are skipped. Returns a freshly-built list.
function LiveEncounter:GetMonsterGroups()
    local q = dmhub.initiativeQueue
    local result = {}
    local seenGroups = {}

    local function AddGroup(groupid, name, memberids, memberinfo)
        if seenGroups[groupid] then
            return
        end
        seenGroups[groupid] = true

        --live members first, then any onset members that are no longer resolved
        --to this group (regrouped/removed tokens), deduped by charid.
        local tokens = {}
        local seenTokens = {}
        for _, tok in ipairs(InitiativeQueue.GetTokensForInitiativeId(groupid) or {}) do
            if tok ~= nil and tok.properties ~= nil and not seenTokens[tok.charid] and not tok.properties:IsHero() then
                seenTokens[tok.charid] = true
                tokens[#tokens+1] = tok
            end
        end

        --Onset members with no token on the map any more: the monster died and
        --was despawned/deleted, or was otherwise removed mid-fight. They still
        --count as (dead) members. Each entry is { tokenid, token, info }: token
        --is the off-map token when it still exists anywhere in the game
        --(portraits still render from it), info the onset display snapshot.
        local missing = {}
        for _, mid in ipairs(memberids or {}) do
            if not seenTokens[mid] then
                seenTokens[mid] = true
                local tok = dmhub.GetTokenById(mid)
                if tok ~= nil and tok.valid and tok.properties ~= nil and not tok.properties:IsHero() then
                    tokens[#tokens+1] = tok
                else
                    local offmap = dmhub.GetCharacterById(mid)
                    if offmap ~= nil and (not offmap.valid or offmap.properties == nil or offmap.properties:IsHero()) then
                        offmap = nil
                    end
                    missing[#missing+1] = {
                        tokenid = mid,
                        token = offmap,
                        info = memberinfo ~= nil and memberinfo[mid] or nil,
                    }
                end
            end
        end

        if #tokens == 0 and #missing == 0 then
            return
        end

        local aliveCount = 0
        local primaryToken = nil
        for _, tok in ipairs(tokens) do
            if not tok.properties:IsDead() then
                aliveCount = aliveCount + 1
            end
            --prefer a non-minion member (a squad's captain) as the face of the group.
            if primaryToken == nil and not tok.properties:try_get("minion", false) then
                primaryToken = tok
            end
        end
        --no live captain: fall back to a dead member's off-map token (a wiped
        --squad still shows its captain's face), then any live member, then any
        --dead member whose token survives.
        if primaryToken == nil then
            for _, m in ipairs(missing) do
                if m.token ~= nil and not m.token.properties:try_get("minion", false) then
                    primaryToken = m.token
                    break
                end
            end
        end
        if primaryToken == nil then
            primaryToken = tokens[1]
        end
        if primaryToken == nil then
            for _, m in ipairs(missing) do
                if m.token ~= nil then
                    primaryToken = m.token
                    break
                end
            end
        end

        --when every member's token is deleted outright, the onset snapshot is
        --all that is left to draw the card from; prefer a non-minion member's.
        local fallbackInfo = nil
        for _, m in ipairs(missing) do
            if m.info ~= nil then
                if fallbackInfo == nil or (fallbackInfo.minion and not m.info.minion) then
                    fallbackInfo = m.info
                end
            end
        end

        local memberCount = #tokens + #missing

        --Composition: the group's members bucketed into captains (non-minions)
        --and minions, each grouped by monster type in order of first appearance,
        --so the victory card can read "Dwarf Driver" over "Dwarf Axethrower x4"
        --rather than "Dwarf Driver x5". nil when any member's kind is unknown
        --(a pre-snapshot queue), in which case the card falls back to "name xN".
        local captains, minions = {}, {}
        local byKey = {}
        local complete = true
        local function AddMember(isMinion, typeName)
            if typeName == nil or typeName == "" then
                complete = false
                return
            end
            local key = (isMinion and "m:" or "c:") .. typeName
            local entry = byKey[key]
            if entry == nil then
                entry = { name = typeName, count = 0, minion = isMinion }
                byKey[key] = entry
                local list = cond(isMinion, minions, captains)
                list[#list+1] = entry
            end
            entry.count = entry.count + 1
        end
        for _, tok in ipairs(tokens) do
            local mtype = tok.properties:try_get("monster_type")
            if mtype == nil or mtype == "" then
                mtype = tok.description
            end
            AddMember(tok.properties:try_get("minion", false) == true, mtype)
        end
        for _, m in ipairs(missing) do
            if m.token ~= nil then
                local mtype = m.token.properties:try_get("monster_type")
                if mtype == nil or mtype == "" then
                    mtype = m.token.description
                end
                AddMember(m.token.properties:try_get("minion", false) == true, mtype)
            elseif m.info ~= nil then
                AddMember(m.info.minion == true, m.info.monsterType)
            else
                complete = false
            end
        end
        local composition = nil
        if complete then
            composition = { captains = captains, minions = minions }
        end

        local displayName = name
        if displayName == nil or displayName == "" then
            local entry = q ~= nil and q.entries[groupid] or nil
            if entry ~= nil and entry:has_key("description") then
                displayName = entry.description
            end
        end
        if displayName == nil or displayName == "" then
            displayName = (primaryToken ~= nil and primaryToken.description) or "Monsters"
        end

        result[#result+1] = {
            groupid = groupid,
            statKey = SanitizeStatKey(groupid),
            name = displayName,
            tokens = tokens,
            memberCount = memberCount,
            aliveCount = aliveCount,
            deadCount = memberCount - aliveCount,
            allDead = aliveCount == 0,
            primaryToken = primaryToken,
            fallbackInfo = fallbackInfo,
            composition = composition,
        }
    end

    for _, g in ipairs(self:GetOnsetMonsterGroups()) do
        AddGroup(g.groupid, g.name, g.memberids, g.memberinfo)
    end

    if q ~= nil then
        --sorted: q.entries is a hash whose order differs between clients, and
        --victory role ties are broken by group order.
        local extraids = {}
        for initiativeid, _ in pairs(q.entries) do
            if not seenGroups[initiativeid] and q:IsEntryPlayer(initiativeid) == false then
                extraids[#extraids+1] = initiativeid
            end
        end
        table.sort(extraids)
        for _, initiativeid in ipairs(extraids) do
            AddGroup(initiativeid, nil, nil)
        end
    end

    return result
end

-- The hero tokens in the battle: every IsHero entry in the initiative queue
-- (deduped), plus any onset hero whose token the queue no longer resolves -- a
-- dead hero can be removed from the battlefield entirely (e.g. the Encounter of
-- the Week hero-death rule despawns them), and the victory screen and battle
-- log must still show everyone who STARTED the fight, not just the survivors.
-- Off-queue heroes resolve via GetCharacterById, which finds despawned tokens
-- anywhere in the game; their stats and role history key off charid as normal.
-- Heroes appear as long as combat is live even when the onset snapshot was
-- never captured (the snapshot only adds the removed ones back). Returns a
-- list of tokens sorted by charid, the same on every client.
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

    --onset heroes the queue no longer resolves (their token was despawned or
    --deleted mid-fight); they still count as participants.
    for _, h in ipairs(self:GetOnsetHeroes()) do
        if not seen[h.charid] then
            seen[h.charid] = true
            local token = dmhub.GetCharacterById(h.charid)
            if token ~= nil and token.valid and token.properties ~= nil and token.properties:IsHero() then
                result[#result + 1] = token
            end
        end
    end
    --q.entries is a hash whose iteration order differs between clients; sort so
    --every client sees the same order (victory role ties are broken by it).
    table.sort(result, function(a, b) return a.charid < b.charid end)
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

-- The per-monster-group statistics table for this encounter, keyed by statKey
-- (the sanitized initiative group id -- see GetMonsterGroups). Same shape as the
-- hero stats table: each group's sub-table is keyed by round ("round1", ...),
-- each round bucket maps statid -> running total. Always a table; read-only.
function LiveEncounter:GetMonsterStats()
    return self:try_get("monsterStats") or {}
end

-- The whole-combat statistics for a single monster group (a map of statid ->
-- total summed across rounds, nested sub-tables deep-merged), or an empty table.
-- statKey is the group's sanitized id from GetMonsterGroups. Freshly built --
-- safe for callers to keep.
function LiveEncounter:GetStatsForMonsterGroup(statKey)
    local result = {}
    for _, roundStats in pairs(self:GetMonsterStats()[statKey] or {}) do
        if type(roundStats) == "table" then
            SumStatsTables(result, roundStats)
        end
    end
    return result
end

-- The per-round statistics recorded for a single monster group: a map of
-- "round<N>" -> { statid = total }, or an empty table. Read-only view.
function LiveEncounter:GetStatsForMonsterGroupByRound(statKey)
    return self:GetMonsterStats()[statKey] or {}
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
--Walk a token's summon chain (falling back to retainer mentor links) up to its
--root owner. Guard against cycles with a visited set and against runaway chains
--with a hard cap. Returns the root token (which may be the token itself), or nil.
--Shared by ResolveStatHero and ResolveStatMonsterGroup so a summon's stats always
--land on whoever summoned it, hero or monster.
local function ResolveStatRootToken(tokenid)
    if tokenid == nil then
        return nil
    end

    local token = dmhub.GetTokenById(tokenid)

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

    if token == nil or not token.valid then
        return nil
    end
    return token
end

function LiveEncounter:ResolveStatHero(tokenid)
    local token = ResolveStatRootToken(tokenid)

    if token == nil or token.properties == nil or not token.properties:IsHero() then
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

-- Resolve the monster initiative grouping a stat should be attributed to, for a
-- token that did NOT resolve to a hero. Follows the same summon-chain walk as
-- ResolveStatHero (a monster's summon credits the summoning monster's group). The
-- root must be a non-hero whose initiative id is a group participating in the
-- current combat -- either it has a live initiative entry, or it appears in the
-- onset snapshot (a group whose entry the director removed mid-fight still
-- accumulates). Returns the group's initiative id, or nil to drop the stat.
function LiveEncounter:ResolveStatMonsterGroup(tokenid)
    local token = ResolveStatRootToken(tokenid)

    if token == nil or token.properties == nil or token.properties:IsHero() then
        return nil
    end

    local groupid = InitiativeQueue.GetInitiativeId(token)
    if groupid == nil then
        return nil
    end

    local q = dmhub.initiativeQueue
    if q ~= nil and q.entries[groupid] ~= nil then
        return groupid
    end

    for _, g in ipairs(self:GetOnsetMonsterGroups()) do
        if g.groupid == groupid then
            return groupid
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
-- The stat is recorded for a valid hero (type "character") in the current combat
-- (under stats/<tokenid>), or -- failing that -- for the acting token's monster
-- initiative grouping (under monsterStats/<groupKey>); summons attribute to their
-- summoner on both sides, and anything that resolves to neither is ignored (see
-- ResolveStatHero / ResolveStatMonsterGroup). The actual add is routed through the
-- server's atomic increment (dmhub:IncrementInitiativeData), so concurrent writers
-- from multiple clients can't lose updates, and the resolved value rides back
-- through the normal initiative-queue broadcast.
function LiveEncounter:IncrementStat(tokenid, statid, quantity)
    if statid == nil or statid == "" then
        return
    end

    if quantity == nil then
        quantity = 1
    end

    --bucket the stat by combat round (round<N> sub-tables) so all stats are
    --recorded per round; whole-combat totals are produced by summing the round
    --buckets on read (see GetStatsForToken / GetStatsForMonsterGroup). "roundN"
    --string keys rather than bare numbers so no serialization layer mistakes the
    --sub-table for an array.
    local round = 0
    local q = dmhub.initiativeQueue
    if q ~= nil then
        round = q.round or 0
    end

    --paths are relative to the initiative queue root; the live encounter rides
    --inside the queue at liveEncounter, with per-hero stats under stats/<tokenid>
    --and per-monster-group stats under monsterStats/<groupKey>.
    local heroToken = self:ResolveStatHero(tokenid)
    if heroToken ~= nil then
        local path = string.format("liveEncounter/stats/%s/round%d/%s", heroToken.charid, round, statid)
        dmhub:IncrementInitiativeData(path, quantity)
        return
    end

    --not a hero: attribute to the acting token's monster initiative grouping, so
    --the same call sites that record hero stats feed the victory screen's
    --Monsters tab too.
    local groupid = self:ResolveStatMonsterGroup(tokenid)
    if groupid ~= nil then
        local path = string.format("liveEncounter/monsterStats/%s/round%d/%s", SanitizeStatKey(groupid), round, statid)
        dmhub:IncrementInitiativeData(path, quantity)
    end
end

-- Convenience entry point for recording a combat stat from anywhere in the codebase
-- without the caller having to find the live encounter or guard any edge cases.
--
--   LiveEncounter.TrackHeroStats(token.charid, "kills")
--
-- "just works": it locates the current combat's live encounter and records the stat
-- against whoever the token resolves to -- a participating hero (under stats), or,
-- failing that, the token's monster initiative grouping (under monsterStats, read
-- by the victory screen's Monsters tab). Summons attribute to their summoner on
-- both sides. If the token resolves to neither (not in this combat, an object,
-- etc.) it quietly does nothing.
--
-- (The name is historical -- it predates monster-group tracking; it is the single
-- entry point for BOTH sides now, and every call site feeds both.)
--
-- This is the safe, static public surface: it is wrapped so it never throws, making
-- it safe to drop directly into hot combat / damage code paths. The actual validation
-- (attribution, summon walking, combat-participation check) and the networked
-- accumulation live in IncrementStat / ResolveStatHero / ResolveStatMonsterGroup.
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

-- Record that a monster initiative group completed a turn (+1 turnsTaken in the
-- current round's bucket of monsterStats/<groupKey>). Called from
-- InitiativeQueue.NextTurn on the client that ends the turn, with the group's
-- initiative id directly -- there is no single token to resolve, so this bypasses
-- the tokenid-based attribution. The "Set Has Moved" skip path deliberately does
-- NOT record a turn, which is what lets the victory screen tell "died before
-- taking a single turn" apart from "had its turns skipped once dead".
-- Safe/static like TrackHeroStats: never throws, no-ops outside live combat.
function LiveEncounter.TrackMonsterGroupTurn(initiativeid)
    local ok, err = pcall(function()
        if initiativeid == nil or initiativeid == "" then
            return
        end

        local q = dmhub.initiativeQueue
        if q == nil or q:try_get("hidden") then
            return
        end

        local live = q:try_get("liveEncounter")
        if type(live) ~= "table" then
            return
        end

        --only monster-side entries are tracked.
        if q:IsEntryPlayer(initiativeid) ~= false then
            return
        end

        local path = string.format("liveEncounter/monsterStats/%s/round%d/turnsTaken", SanitizeStatKey(initiativeid), q.round or 0)
        dmhub:IncrementInitiativeData(path, 1)
    end)

    if not ok then
        dmhub.Debug(string.format("LiveEncounter.TrackMonsterGroupTurn: failed: %s", tostring(err)))
    end
end

-- The display name of the live encounter (the live encounter is itself a copy of
-- the authored encounter, so this is just its name).
function LiveEncounter:GetName()
    return self:try_get("name")
end

-- The combat outcome the director has awarded, if any: "victory", "defeat", or
-- nil while the encounter is still being fought. Victory wins if both flags are
-- somehow set. Use this (rather than checking victoryAwarded directly) anywhere
-- that hides combat UI while the full-screen outcome screen is up.
function LiveEncounter:GetAwardedOutcome()
    if self:try_get("victoryAwarded", false) then
        return "victory"
    end
    if self:try_get("defeatAwarded", false) then
        return "defeat"
    end
    return nil
end

----------------------------------------------------------------------
-- Battle log + the encounter_complete analytics event
--
-- When an encounter ends, the director's client does two things exactly once:
--
--  1. Appends a permanent record of the battle to the game's BATTLE LOG (a
--     shared document, so every client can read it and it outlives the
--     initiative queue being torn down). This is the reviewable campaign
--     history: what was fought, how it ended, and who did what.
--  2. Emits the encounter_complete ANALYTICS EVENT -- the same header plus the
--     full per-hero stat dump and a "seriousness" assessment, so offline
--     reporting can tell a real play session apart from a test or a preview.
--
-- The two deliberately carry different detail. The log lives inside gameDetails,
-- which every client downloads in full on load, so it keeps only the headline
-- numbers per hero and is capped at BattleLog.maxRecords. The analytics event is
-- a one-shot push that is never stored in the game, so it carries everything.
--
-- Both are driven by LiveEncounter.CompleteEncounter(outcome), called from the
-- two places combat can end: the outcome screen's Proceed button
-- (Draw Steel UI/DSVictoryScreen.lua) and the initiative bar's End Combat
-- (MCDMInitiativeBar.lua). Never throws -- ending combat must not be able to
-- fail because of bookkeeping.
----------------------------------------------------------------------

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

BattleLog = {}

-- The shared document holding the battle log, keyed by battle id.
BattleLog.docId = "dsBattleLog"

-- How many battles to keep. The log rides inside gameDetails, which every client
-- downloads in full on load, so it is bounded: recording battle N+1 prunes the
-- oldest.
--
-- SIZE: measured, not estimated. A real record built against a live 5-hero fight
-- is ~2KB of JSON (guids and key names dominate; zero stats are already omitted
-- and the analytics-only payload is already excluded). So this cap is what the log
-- adds to every client's game load:
--
--     100 -> ~195KB       150 -> ~295KB       200 -> ~390KB
--
-- 200 is roughly a year and a half for a weekly group running two fights a
-- session. Lower it here if the load cost matters more than the history depth.
BattleLog.maxRecords = 200

mod:RegisterDocumentForCheckpointBackups(BattleLog.docId)

-- The document path, for panels that want to monitorGame the log.
function BattleLog.GetDocPath()
    return mod:GetDocumentPath(BattleLog.docId)
end

-- Every recorded battle, newest first. Each entry is the record built by
-- LiveEncounter:BuildBattleRecord (see there for the field list). Always a list;
-- empty when nothing has been recorded in this game yet.
function BattleLog.GetBattles()
    local result = {}
    local doc = mod:GetDocumentSnapshot(BattleLog.docId)
    local battles = doc.data.battles
    if type(battles) ~= "table" then
        return result
    end

    --Read-only: these tables belong to the live document, so nothing here
    --mutates them (an unannounced write would show up as a spurious diff the
    --next time anything calls BeginChange on this document).
    for _, record in pairs(battles) do
        if type(record) == "table" then
            result[#result + 1] = record
        end
    end

    table.sort(result, function(a, b)
        local at = a.t or 0
        local bt = b.t or 0
        if at ~= bt then
            return at > bt
        end
        return tostring(a.id) < tostring(b.id)
    end)

    return result
end

-- One battle by id, or nil.
function BattleLog.GetBattle(battleid)
    if battleid == nil then
        return nil
    end
    local doc = mod:GetDocumentSnapshot(BattleLog.docId)
    local battles = doc.data.battles
    if type(battles) ~= "table" then
        return nil
    end
    local record = battles[battleid]
    if type(record) ~= "table" then
        return nil
    end
    return record
end

-- Append a battle record and prune the oldest beyond BattleLog.maxRecords.
-- Keyed by record.id (the combat's guid), so a double-record of the same combat
-- overwrites rather than duplicating. Director-only in practice -- the callers
-- gate on it -- so there is no concurrent-writer problem. Returns true if the
-- record was written.
function BattleLog.RecordBattle(record)
    if type(record) ~= "table" or record.id == nil then
        return false
    end

    local doc = mod:GetDocumentSnapshot(BattleLog.docId)
    doc:BeginChange()
    if type(doc.data.battles) ~= "table" then
        doc.data.battles = {}
    end
    doc.data.battles[record.id] = record

    --prune the oldest records beyond the cap. Collect (id, t) pairs, sort
    --oldest-first, and drop the excess.
    local ordered = {}
    for id, entry in pairs(doc.data.battles) do
        if type(entry) == "table" then
            ordered[#ordered + 1] = { id = id, t = entry.t or 0 }
        else
            --junk value; drop it.
            doc.data.battles[id] = nil
        end
    end
    if #ordered > BattleLog.maxRecords then
        table.sort(ordered, function(a, b)
            if a.t ~= b.t then
                return a.t < b.t
            end
            return tostring(a.id) < tostring(b.id)
        end)
        local excess = #ordered - BattleLog.maxRecords
        for i = 1, excess do
            doc.data.battles[ordered[i].id] = nil
        end
    end

    doc:CompleteChange("Record battle", { undoable = false })
    return true
end

-- Delete every recorded battle. For the director, and for testing.
function BattleLog.Clear()
    local doc = mod:GetDocumentSnapshot(BattleLog.docId)
    if type(doc.data.battles) ~= "table" then
        return
    end
    doc:BeginChange()
    doc.data.battles = {}
    doc:CompleteChange("Clear battle log", { undoable = false })
end

-- Seriousness thresholds. An encounter must clear ALL of these to be recorded as
-- a real play session; the raw inputs are stored on the record either way, so
-- offline reporting can re-derive the verdict with its own thresholds without a
-- client change.
local BATTLE_MIN_USERS = 3        -- connected users (director + players)
local BATTLE_MIN_ROUNDS = 2       -- a one-round combat is almost always a test
local BATTLE_MIN_HEROES = 2       -- a party, not a single token being poked at
local BATTLE_MIN_SECONDS = 180    -- only checked when the onset time is known

-- The users actually present for this combat: their userids, how many are
-- players (not directors), and the total. "Present" is CountLoggedInUsers'
-- definition -- not logged out and seen within the last 2 minutes -- because
-- dmhub.users keeps stale entries for people who left the session long ago.
-- Returns playerIds (a list of non-director userids), playerCount, total.
local function BattlePresentUsers()
    local playerIds = {}
    local total = 0
    pcall(function()
        for _, userid in ipairs(dmhub.users or {}) do
            local info = dmhub.GetSessionInfo(userid)
            if info ~= nil and (not info.loggedOut) and info.timeSinceLastContact < 120 then
                total = total + 1
                if not info.dm then
                    playerIds[#playerIds + 1] = userid
                end
            end
        end
    end)
    return playerIds, #playerIds, total
end

-- nil for zero, the value otherwise. Used all through the battle record: a stat
-- that is absent reads back as 0 anyway (BattleStatTotal and the UI both default
-- it), and most heroes score nothing on most stats, so dropping the zeros roughly
-- halves what the log costs inside gameDetails. Never apply this to a value where
-- "absent" and "zero" must be distinguishable.
local function BattleNonZero(v)
    if type(v) ~= "number" or v == 0 then
        return nil
    end
    return v
end

-- A hero's display name. token.name is frequently nil (it is the optional
-- override); token.description is the name actually shown in game.
local function BattleTokenName(token)
    if token == nil then
        return nil
    end
    if type(token.name) == "string" and token.name ~= "" then
        return token.name
    end
    if type(token.description) == "string" and token.description ~= "" then
        return token.description
    end
    return nil
end

-- Sum one numeric stat across a hero's whole encounter, tolerating a missing or
-- nested value. totals comes from GetStatsForToken (already round-summed).
local function BattleStatTotal(totals, statid)
    local v = totals ~= nil and totals[statid] or nil
    if type(v) == "number" then
        return v
    end
    return 0
end

-- Sum every numeric leaf of a nested stat sub-table (tierRolls,
-- conditionsInflicted, ...). Returns 0 when the stat was never recorded.
local function BattleStatNestedTotal(totals, statid)
    local t = totals ~= nil and totals[statid] or nil
    if type(t) ~= "table" then
        return 0
    end
    local sum = 0
    for _, v in pairs(t) do
        if type(v) == "number" then
            sum = sum + v
        end
    end
    return sum
end

-- Build the permanent record of this encounter.
--
-- outcome is "victory", "defeat", or "ended" (combat closed without the director
-- awarding either). roles is the hero-role map from
-- DSVictoryScreen.ComputeHeroRoles; pass the same table the outcome screen
-- displayed, because role selection is biased by each hero's role history and
-- recomputing it after that history has been bumped can yield different roles.
--
-- Returns nil when there is nothing worth recording (no heroes, no rounds, or a
-- combat in which no blow was struck -- respite/downtime queues end through the
-- same code path). Otherwise the record is:
--
--   id, t, durationSeconds,
--   name (encounter name; nil for a Custom combat), outcome, rounds, eds,
--   mapid, mapName, serious, notSerious,
--   heroes  = { { charid, name, ownerId, class, subclass, ancestry, level,
--                 role, roleText, survived, damage, taken, prevented,
--                 kills, minionKills, criticals,
--                 recoveriesStart, recoveriesEnd }, ... },
--   monsters = { { name, monster, role, count, dead,
--                  damage, taken, deaths, turns, battleRole }, ... },
--   party = { damage, taken, prevented, kills, minionKills, downed, deaths },
--   analytics = { ... }   -- lifted off and dropped by CompleteEncounter
--
-- Zero-valued stats are omitted throughout (see BattleNonZero) -- read them back
-- with a `or 0` default. The per-hero set is deliberately the headline numbers
-- only: the full stat dump and every seriousness input ride in `analytics`, which
-- goes to the event and never into the game document.
function LiveEncounter:BuildBattleRecord(outcome, roles)
    local q = dmhub.initiativeQueue
    local heroTokens = self:GetBattleHeroTokens()
    local groups = self:GetMonsterGroups()
    local rounds = (q ~= nil and q.round) or 0

    if #heroTokens == 0 or rounds < 1 then
        return nil
    end

    if type(roles) ~= "table" then
        roles = {}
        local victoryScreen = rawget(_G, "DSVictoryScreen")
        if victoryScreen ~= nil then
            pcall(function() roles = victoryScreen.ComputeHeroRoles(self) or {} end)
        end
    end

    local monsterRoles = {}
    do
        local victoryScreen = rawget(_G, "DSVictoryScreen")
        if victoryScreen ~= nil then
            pcall(function() monsterRoles = victoryScreen.ComputeMonsterRoles(self) or {} end)
        end
    end

    local party = {
        damage = 0,
        taken = 0,
        prevented = 0,
        kills = 0,
        minionKills = 0,
        downed = 0,
        deaths = 0,
    }

    local owners = {}
    local ownerCount = 0
    local heroes = {}
    local fullStats = {}

    for _, token in ipairs(heroTokens) do
        local props = token.properties
        local totals = self:GetStatsForToken(token.charid) or {}

        local className = nil
        local classInfo = nil
        pcall(function() classInfo = props:GetClass() end)
        if classInfo ~= nil then
            className = classInfo.name
        end

        local subclassName = nil
        pcall(function()
            for _, entry in ipairs(props:GetSubclasses() or {}) do
                if subclassName == nil then
                    subclassName = entry.name
                else
                    subclassName = subclassName .. "/" .. entry.name
                end
            end
        end)

        local ancestry = nil
        pcall(function() ancestry = props:RaceOrMonsterType() end)

        local level = nil
        pcall(function() level = props:Level() end)

        local dead = false
        pcall(function() dead = props:IsDead() end)
        local dying = false
        pcall(function() dying = props:IsDying() end)

        local onsetRecoveries, currentRecoveries = self:GetHeroRecoveries(token)

        --ownerId is the userid of the player who owns this hero, or the string
        --"PARTY" for a party-owned token, or nil for a director-controlled one.
        --Party ownership is common and a party has no user membership to resolve
        --against, so ownerCount is 0 for such a group -- see the note on
        --record.players below.
        local ownerId = token.ownerId
        if type(ownerId) == "string" and ownerId ~= "" and ownerId ~= "PARTY" and not owners[ownerId] then
            owners[ownerId] = true
            ownerCount = ownerCount + 1
        end

        local roleInfo = roles[token.charid]

        local tierRolls = totals.tierRolls
        if type(tierRolls) ~= "table" then
            tierRolls = {}
        end

        local damage = BattleStatTotal(totals, "damageDealt")
        local taken = BattleStatTotal(totals, "damageTaken")
        local prevented = BattleStatTotal(totals, "damagePrevention")
        local kills = BattleStatTotal(totals, "kills")
        local minionKills = BattleStatTotal(totals, "minionKills")
        local criticals = BattleStatTotal(totals, "criticals")

        party.damage = party.damage + damage
        party.taken = party.taken + taken
        party.prevented = party.prevented + prevented
        party.kills = party.kills + kills
        party.minionKills = party.minionKills + minionKills
        if dead then
            party.deaths = party.deaths + 1
        elseif dying then
            party.downed = party.downed + 1
        end

        heroes[#heroes + 1] = {
            charid = token.charid,
            name = BattleTokenName(token),
            ownerId = ownerId,
            class = className,
            subclass = subclassName,
            ancestry = ancestry,
            level = level,
            role = roleInfo ~= nil and roleInfo.role or nil,
            roleText = roleInfo ~= nil and roleInfo.text or nil,
            survived = not dead,
            damage = BattleNonZero(damage),
            taken = BattleNonZero(taken),
            prevented = BattleNonZero(prevented),
            kills = BattleNonZero(kills),
            minionKills = BattleNonZero(minionKills),
            criticals = BattleNonZero(criticals),
            recoveriesStart = onsetRecoveries,
            recoveriesEnd = currentRecoveries,
        }

        --the analytics-only expansion: everything else the encounter tracked.
        fullStats[#fullStats + 1] = {
            charid = token.charid,
            ownerId = ownerId,
            class = className,
            subclass = subclassName,
            ancestry = ancestry,
            level = level,
            role = roleInfo ~= nil and roleInfo.role or nil,
            --nil when they won the role outright; "cascade" / "floor" when the
            --awarder had to fall back. See TrackHeroRoleFallbacks below.
            roleFallback = roleInfo ~= nil and roleInfo.fallback or nil,
            survived = not dead,
            damage = damage,
            taken = taken,
            prevented = prevented,
            kills = kills,
            minionKills = minionKills,
            criticals = criticals,
            overkill = BattleStatTotal(totals, "overkill"),
            spacesMoved = BattleStatTotal(totals, "spacesMoved"),
            allyDamageDealt = BattleStatTotal(totals, "allyDamageDealt"),
            enemyTurnDamage = BattleStatTotal(totals, "enemyTurnDamage"),
            forcedMovementDealt = BattleStatTotal(totals, "forcedMovementDealt"),
            forcedMovementTaken = BattleStatTotal(totals, "forcedMovementTaken"),
            standsFirm = BattleStatTotal(totals, "standsFirm"),
            resourcesGained = BattleStatTotal(totals, "heroicResourcesGained"),
            resourcesSpent = BattleStatTotal(totals, "heroicResourcesSpent"),
            edges = BattleStatTotal(totals, "edges"),
            banes = BattleStatTotal(totals, "banes"),
            tier1 = BattleStatTotal(tierRolls, "tier1"),
            tier2 = BattleStatTotal(tierRolls, "tier2"),
            tier3 = BattleStatTotal(tierRolls, "tier3"),
            conditionsInflicted = BattleStatNestedTotal(totals, "conditionsInflicted"),
            conditionsReceived = BattleStatNestedTotal(totals, "conditionsReceived"),
            recoveriesSpent = (onsetRecoveries ~= nil and currentRecoveries ~= nil)
                and math.max(0, onsetRecoveries - currentRecoveries) or nil,
        }
    end

    local monsters = {}
    local monsterCount = 0
    for _, group in ipairs(groups) do
        local totals = self:GetStatsForMonsterGroup(group.statKey) or {}
        monsterCount = monsterCount + group.memberCount

        local monsterType = nil
        local monsterRole = nil
        local primary = group.primaryToken
        if primary ~= nil and primary.properties ~= nil then
            monsterType = primary.properties:try_get("monster_type")
            local r = primary.properties:try_get("role")
            if r ~= nil and r ~= "" then
                monsterRole = r
            end
        elseif group.fallbackInfo ~= nil then
            --every member token was deleted; the onset snapshot still knows what
            --this group was.
            monsterType = group.fallbackInfo.monsterType
            monsterRole = group.fallbackInfo.role
        end

        local groupRoleInfo = monsterRoles[group.groupid]

        --No groupid and no allDead: the initiative id is only useful for keying
        --the live stats table, which is gone by the time anything reads this back,
        --and allDead is just count == dead.
        monsters[#monsters + 1] = {
            name = group.name,
            monster = monsterType,
            role = monsterRole,
            count = group.memberCount,
            dead = BattleNonZero(group.deadCount),
            damage = BattleNonZero(BattleStatTotal(totals, "damageDealt")),
            taken = BattleNonZero(BattleStatTotal(totals, "damageTaken")),
            deaths = BattleNonZero(BattleStatTotal(totals, "deaths")),
            turns = BattleNonZero(BattleStatTotal(totals, "turnsTaken")),
            battleRole = groupRoleInfo ~= nil and groupRoleInfo.role or nil,
        }
    end

    --Nothing actually happened: no blow was struck in either direction. This is a
    --combat that was opened and closed again, or a respite / downtime queue (they
    --end through the same End Combat path). Not a battle -- do not put it in the
    --player-visible log at all. Every real fight lands damage one way or the
    --other, and kills imply damage dealt while deaths imply damage taken, so this
    --single test covers them too. Note this is a stricter bar than `serious`:
    --a short scrappy fight is logged but may well not be serious.
    if party.damage <= 0 and party.taken <= 0 then
        return nil
    end

    --Connected users at the end of combat, and at the start. Seriousness uses the
    --larger: a player dropping before the director presses Proceed must not make a
    --four-person session look like a solo test, and someone joining mid-fight
    --should still count.
    local playerIds, playerCount, usercount = BattlePresentUsers()
    local onsetUsercount = self:try_get("onsetUsercount", 0)
    if type(onsetUsercount) ~= "number" then
        onsetUsercount = 0
    end
    local peakUsercount = math.max(usercount, onsetUsercount)

    local startedAt = self:try_get("onsetTimestamp")
    if type(startedAt) ~= "number" or startedAt <= 0 then
        startedAt = nil
    end
    local now = dmhub.serverTimeMilliseconds
    local durationSeconds = nil
    if startedAt ~= nil then
        durationSeconds = math.max(0, math.floor((now - startedAt) / 1000))
    end

    local eds = nil
    pcall(function() eds = self:CountEDS() end)
    if type(eds) ~= "number" or eds <= 0 then
        eds = nil
    end

    local name = self:GetName()
    if name == "" then
        name = nil
    end

    --Seriousness: was this an actual play session working through an actual
    --encounter, rather than a test, a preview, or someone poking at a token?
    local failed = {}
    if dmhub.isLobbyGame then
        failed[#failed + 1] = "lobby"
    end
    if dmhub.harnessMode ~= nil then
        failed[#failed + 1] = "harness"
    end
    if peakUsercount < BATTLE_MIN_USERS then
        failed[#failed + 1] = "users"
    end
    if rounds < BATTLE_MIN_ROUNDS then
        failed[#failed + 1] = "rounds"
    end
    if #heroTokens < BATTLE_MIN_HEROES then
        failed[#failed + 1] = "heroes"
    end
    if #monsters == 0 then
        failed[#failed + 1] = "monsters"
    end
    if party.damage <= 0 then
        failed[#failed + 1] = "damage"
    end
    if durationSeconds ~= nil and durationSeconds < BATTLE_MIN_SECONDS then
        failed[#failed + 1] = "duration"
    end
    if outcome ~= "victory" and outcome ~= "defeat" then
        failed[#failed + 1] = "outcome"
    end

    --The STORED record. Only what a player reviewing their campaign's battles
    --needs: everything here is paid for by every client on every game load, so
    --anything that exists purely for offline reporting goes in `analytics` below
    --instead. startedAt is omitted as derivable (t - durationSeconds * 1000).
    local record = {
        --the combat's guid, so re-recording the same combat overwrites.
        id = (q ~= nil and q:try_get("guid")) or dmhub.GenerateGuid(),
        t = now,
        durationSeconds = durationSeconds,
        name = name,
        outcome = outcome,
        rounds = rounds,
        eds = eds,
        mapid = game.currentMapId,
        mapName = (game.currentMap ~= nil and game.currentMap.description) or nil,
        --kept because a review UI wants to separate real battles from the
        --leftovers of a test; the inputs behind it are analytics-only.
        serious = #failed == 0,
        heroes = heroes,
        monsters = monsters,
        party = party,
    }
    if #failed > 0 then
        record.notSerious = table.concat(failed, ",")
    end

    --Carried out to the caller for the encounter_complete event ONLY.
    --CompleteEncounter strips this before the record is written, so none of it
    --reaches the game document. (The record is a plain table, so the _tmp_
    --game-type convention does not apply -- the stripping is what keeps it out.)
    record.analytics = {
        heroStats = fullStats,
        monsterCount = monsterCount,
        usercount = usercount,
        onsetUsercount = onsetUsercount,
        playerCount = playerCount,
        ownerCount = ownerCount,
        --The connected non-director userids: the reliable answer to "who was in
        --this session", and the only one when the party's heroes are PARTY-owned
        --(ownerCount is 0 then -- a party has no user membership to resolve
        --against). Per-hero attribution needs individually-owned tokens, or a
        --player-side emit.
        players = playerIds,
    }

    return record
end

----------------------------------------------------------------------
-- hero_role_fallback: heroes the role set had nothing to say about
--
-- Every hero now finishes every fight with a title, but not every title is
-- earned. The three assignment passes in Draw Steel UI/DSVictoryScreen.lua go:
-- win it outright (`fallback` nil), inherit an unawarded role as its runner-up
-- ("cascade"), or take a floor role that asks nothing of you at all ("floor" --
-- Pacifist, Tourist, Backbone). A non-nil `fallback` is the interesting signal:
-- the role set had nothing this hero was actually BEST at, and the awarder had
-- to reach for a consolation. That is what this event measures -- how often it
-- happens in a real fight, to which kind of hero, and what they were doing while
-- everyone else was winning something -- so new roles can be designed to cover
-- the gap and the fallbacks can wither away.
--
-- One event per encounter with at least one fallback. It is deliberately
-- SELF-CONTAINED -- the whole party's stat lines ride along, not just the
-- fallback heroes' -- because "why was there no title for this hero" is only
-- answerable next to what the rest of the party did. It also carries the winning
-- line of every role that was in contention, which is the bar they failed to
-- clear. Joins to encounter_complete on battleid.
--
-- Kept OUT of encounter_complete on purpose: that fires for every fight, and
-- this is several KB of diagnostic detail that only matters for the fights that
-- have the problem.
--
-- Gating is deliberately looser than `serious`: lobby and harness combats are
-- dropped (they are never real play), but everything else is sent with the full
-- seriousness verdict attached, so offline reporting filters on `serious` /
-- `notSerious` rather than being starved of cases by the client's thresholds.
local function TrackHeroRoleFallbacks(live, record, extra)
    --never real play; the lobby is a solo character-creation game and the
    --harness is a fixture surface.
    if dmhub.isLobbyGame or dmhub.harnessMode ~= nil then
        return
    end

    local heroStats = extra.heroStats
    if type(heroStats) ~= "table" or #heroStats == 0 then
        return
    end

    --The full eligibility picture, computed the way the outcome screen computed
    --it. Safe to compute here: CompleteEncounter runs BEFORE RecordHeroRoles
    --bumps the per-hero role history that biases selection, so this still
    --reproduces exactly what the players were just looking at.
    local victoryScreen = rawget(_G, "DSVictoryScreen")
    if victoryScreen == nil then
        return
    end
    local debugInfo = nil
    pcall(function() debugInfo = victoryScreen.ComputeHeroRoleDebugInfo(live) end)
    if type(debugInfo) ~= "table" or #debugInfo == 0 then
        return
    end

    --Who was awarded what. This comes from the role map the outcome screen
    --actually displayed (passed into BuildBattleRecord), so it -- not the
    --recomputed debug info -- is what decides who fell back.
    local statsByChar = {}
    local roleHolder = {}
    local awardedList = {}
    for _, h in ipairs(heroStats) do
        statsByChar[h.charid] = h
        if h.role ~= nil then
            roleHolder[h.role] = h.charid
            awardedList[#awardedList + 1] = h.role
        end
    end

    local roleWinners = {}
    local fallbacks = {}
    local cascadeCount = 0
    local floorCount = 0
    local noRoleCount = 0
    for _, info in ipairs(debugInfo) do
        local stats = statsByChar[info.charid]
        local eligible = info.eligible or {}

        --rank 1 in a hero's eligibility list IS that role's winner, so scanning
        --every hero reconstructs the whole contest. `awarded` marks the roles
        --that were handed out at all; `cascaded` marks the ones whose rank-1
        --hero showed something better and whose runner-up inherited it. A role
        --with neither is one the fight had no room for.
        for _, e in ipairs(eligible) do
            if e.rank == 1 then
                local holder = roleHolder[e.role]
                roleWinners[#roleWinners + 1] = {
                    role = e.role,
                    charid = info.charid,
                    class = stats ~= nil and stats.class or nil,
                    text = e.text,
                    awarded = holder ~= nil,
                    cascaded = (holder ~= nil and holder ~= info.charid) or nil,
                    floor = e.isFloor or nil,
                }
            end
        end

        local fallback = stats ~= nil and stats.roleFallback or nil
        if stats ~= nil and stats.role == nil then
            --Should be unreachable: the floor roles cover every hero between
            --them. Counted as a canary -- if this is ever above zero in the
            --data, that coverage broke.
            noRoleCount = noRoleCount + 1
            fallback = "none"
        end

        if fallback ~= nil then
            if fallback == "cascade" then
                cascadeCount = cascadeCount + 1
            elseif fallback == "floor" then
                floorCount = floorCount + 1
            end

            --The actionable half. A hero who placed 2nd in four roles is a
            --tie-break problem; a hero who qualified for nothing at all needs a
            --new role built for whatever they were doing instead. `text` is the
            --role's own phrasing of their number ("Dealt 40 damage"), so a case
            --reads without cross-referencing the stat ids.
            local placings = {}
            for _, e in ipairs(eligible) do
                placings[#placings + 1] = { role = e.role, rank = e.rank, text = e.text }
            end

            fallbacks[#fallbacks + 1] = {
                charid = info.charid,
                fallback = fallback,
                role = stats.role,
                class = stats.class,
                subclass = stats.subclass,
                ancestry = stats.ancestry,
                level = stats.level,
                survived = stats.survived,
                damage = stats.damage,
                taken = stats.taken,
                prevented = stats.prevented,
                kills = stats.kills,
                minionKills = stats.minionKills,
                criticals = stats.criticals,
                conditionsInflicted = stats.conditionsInflicted,
                eligibleCount = #placings,
                eligible = placings,
            }
        end
    end

    if #fallbacks == 0 then
        return
    end

    local fallbackClasses = {}
    local fallbackRoles = {}
    for _, h in ipairs(fallbacks) do
        fallbackClasses[#fallbackClasses + 1] = h.class or "?"
        fallbackRoles[#fallbackRoles + 1] = h.role or "?"
    end

    track("hero_role_fallback", {
        --the join key back to encounter_complete and the battle log.
        battleid = record.id,
        encounter = record.name,
        outcome = record.outcome,
        rounds = record.rounds,
        durationSeconds = record.durationSeconds,
        eds = record.eds,
        mapName = record.mapName,

        --seriousness, carried in full so this table can be filtered exactly like
        --encounter_complete without a join.
        serious = record.serious,
        notSerious = record.notSerious,
        usercount = extra.usercount,
        onsetUsercount = extra.onsetUsercount,
        playerCount = extra.playerCount,

        heroCount = #record.heroes,
        monsterGroupCount = #record.monsters,
        monsterCount = extra.monsterCount,
        partyDamage = record.party.damage,
        partyTaken = record.party.taken,

        --the headline: how many heroes had to be given a title rather than
        --winning one, how far the awarder had to reach, which classes they were,
        --and which roles the fight handed out in total. floorCount is the number
        --that even the cascade could not cover -- the metric to drive to zero by
        --adding roles. noRoleCount should always be 0 (see the canary above).
        fallbackCount = #fallbacks,
        cascadeCount = cascadeCount,
        floorCount = floorCount,
        noRoleCount = noRoleCount,
        fallbackClasses = table.concat(fallbackClasses, ","),
        fallbackRoles = table.concat(fallbackRoles, ","),
        rolesAwarded = table.concat(awardedList, ","),
        rolesAwardedCount = #awardedList,

        --the detail: each fallback hero with the roles they placed in but did
        --not win, every role's winning line (awarded, cascaded, or neither), and
        --the whole party's full stat dump for context.
        fallbacks = fallbacks,
        roleWinners = roleWinners,
        heroes = heroStats,

        dailyLimit = 20,
    })
end

-- Called once, on the director's client, when an encounter ends: writes the
-- battle log entry and emits the encounter_complete analytics event.
--
-- outcome is "victory" / "defeat" / "ended". roles is optional -- pass the role
-- map the outcome screen displayed so the recorded roles match what players saw
-- (see BuildBattleRecord). Safe to call unconditionally: it no-ops for players,
-- for a second call on the same combat, and for anything that was not a fight,
-- and it never throws.
function LiveEncounter.CompleteEncounter(outcome, roles)
    local ok, err = pcall(function()
        --hosting capability: the EotW player host is the client that must
        --record the battle log and analytics.
        if not IsDMOrPlayerHost() then
            return
        end

        local q = dmhub.initiativeQueue
        if q == nil then
            return
        end

        local live = q:try_get("liveEncounter")
        if type(live) ~= "table" then
            return
        end

        --single-fire per combat. Transient, which is all that is needed: only
        --this client can re-enter the end-combat paths before the queue is torn
        --down, and the record is keyed by the combat guid anyway.
        if live:try_get("_tmp_dsBattleRecorded", false) then
            return
        end
        live._tmp_dsBattleRecorded = true

        local record = live:BuildBattleRecord(outcome, roles)
        if record == nil then
            return
        end

        --Lift the analytics-only payload off the record BEFORE storing it, so
        --none of it lands in the game document.
        local extra = record.analytics or {}
        record.analytics = nil

        BattleLog.RecordBattle(record)

        --malice is the director's side of the economy; a missing/zeroed resource
        --must not cost us the whole event.
        local maliceRemaining = nil
        pcall(function() maliceRemaining = CharacterResource.GetMalice() end)

        local monsterNames = {}
        local monsterRoleNames = {}
        for _, m in ipairs(record.monsters) do
            if m.monster ~= nil then
                monsterNames[#monsterNames + 1] = m.monster
            end
            if m.role ~= nil then
                monsterRoleNames[#monsterRoleNames + 1] = m.role
            end
        end

        track("encounter_complete", {
            battleid = record.id,
            encounter = record.name,
            outcome = record.outcome,
            rounds = record.rounds,
            eds = record.eds,
            mapid = record.mapid,
            mapName = record.mapName,
            durationSeconds = record.durationSeconds,

            --seriousness: the verdict plus every input behind it, so offline
            --reporting can re-derive it with different thresholds.
            serious = record.serious,
            notSerious = record.notSerious,
            usercount = extra.usercount,
            onsetUsercount = extra.onsetUsercount,
            playerCount = extra.playerCount,
            ownerCount = extra.ownerCount,
            players = table.concat(extra.players or {}, ","),
            heroCount = #record.heroes,
            monsterGroupCount = #record.monsters,
            monsterCount = extra.monsterCount,
            lobby = dmhub.isLobbyGame,

            monsterTypes = table.concat(monsterNames, ","),
            monsterRoles = table.concat(monsterRoleNames, ","),

            partyDamage = record.party.damage,
            partyTaken = record.party.taken,
            partyPrevented = record.party.prevented,
            partyKills = record.party.kills,
            partyMinionKills = record.party.minionKills,
            heroesDowned = record.party.downed,
            heroesDead = record.party.deaths,
            maliceRemaining = maliceRemaining,

            heroes = extra.heroStats,
            monsters = record.monsters,

            dailyLimit = 20,
        })

        --And, only when somebody had to be handed a role rather than winning
        --one, the diagnostic feed for closing that gap. Its own pcall: a failure
        --computing role eligibility must not lose the encounter_complete event
        --above, which has already been sent, nor stop combat from ending.
        pcall(TrackHeroRoleFallbacks, live, record, extra)
    end)

    if not ok then
        dmhub.Debug(string.format("BattleLog: CompleteEncounter failed: %s", tostring(err)))
    end
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

-- ===========================================================================
-- Encounter region and hero start zone
-- ===========================================================================
--
-- Both are drawn in the encounter builder (EncounterPanel.lua) on the
-- encounter's map.
--
-- region: the rectangle of the map the encounter takes place in, in tile
-- coordinates, corners inclusive: { x1, y1, x2, y2 }. Unset = the entire
-- map. When combat starts on it the map's bounds shrink to the region, and
-- they grow back when combat ends. The original bounds are kept in a shared
-- document, not in memory, so a crash or a combat ended from anywhere (the
-- victory screen, End Combat, a respite) still restores them.
--
-- heroStartLocs: the tiles heroes may start on, { {x, y, floor = floorid} }.
-- Unset or empty = no start zone. Once the encounter is placed on the map,
-- every client shows the zone and players' tokens can only move inside it,
-- until combat starts.

--- @alias EncounterRegion {x1: number, y1: number, x2: number, y2: number}
--- @alias EncounterStartLoc {x: number, y: number, floor: string}

--- @return EncounterRegion|nil
function Encounter:GetRegion()
    local region = self:try_get("region")
    if type(region) ~= "table" or region.x1 == nil then
        return nil
    end
    return region
end

--- @param region EncounterRegion|nil nil = the entire map.
function Encounter:SetRegion(region)
    self.region = region
end

--- @return EncounterStartLoc[]
function Encounter:GetHeroStartLocs()
    local locs = self:try_get("heroStartLocs")
    if type(locs) ~= "table" then
        return {}
    end
    return locs
end

--- @param locs EncounterStartLoc[]|nil nil or empty = no start zone.
function Encounter:SetHeroStartLocs(locs)
    if locs ~= nil and #locs == 0 then
        locs = nil
    end
    self.heroStartLocs = locs
end

--- @alias EncounterMapRef {pack: string, mapid: string, name: string}

--The Map Library map the encounter is set on (see Encounter.mapRef), or nil.
--- @return EncounterMapRef|nil
function Encounter:GetMapRef()
    local value = self:try_get("mapRef")
    if type(value) ~= "string" or value == "" or rawget(_G, "CustomDocument") == nil then
        return nil
    end
    return CustomDocument.ParseLibraryMap(value)
end

--The map in this game that a library map ref names, or nil if it has not
--been added. Found by where the map came from (packSource), so a second
--copy, which gets fresh ids, is found too; the copy keeping the pack's id wins.
--- @param ref EncounterMapRef
--- @return MapManifestLua|nil
function Encounter.FindLibraryMap(ref)
    local found = nil
    for _, map in ipairs(game.maps) do
        local source = map.packSource
        if map.valid and source ~= nil and source.pack == ref.pack and source.mapid == ref.mapid then
            if map.id == ref.mapid then
                return map
            end
            found = found or map
        end
    end
    return found
end

--Where a shipped encounter comes from, for grouping it in the Encounters
--list, or nil for one made in this game. Shipped delve encounters carry
--{source = "Draw Steel: Encounters", delve = "Aixco Hollow", level = 1, area = "A1", page = 11}.
--- @alias EncounterBookInfo {source: string, delve: string, level: number, area: string, page: number|nil}
--- @return EncounterBookInfo|nil
function Encounter:GetBookInfo()
    local book = self:try_get("book")
    if type(book) ~= "table" or type(book.delve) ~= "string" then
        return nil
    end
    return book
end

--The start tiles that lie on the current map's floors, as placeable locs.
--Tiles on a floor the map no longer has are skipped.
--- @param startLocs EncounterStartLoc[]
--- @return Loc[]
function Encounter.StartLocsOnCurrentMap(startLocs)
    local floorIndexById = {}
    local map = game.currentMap
    if map ~= nil then
        for _, floor in ipairs(map.floors or {}) do
            pcall(function()
                if floor.floorIndex >= 0 then
                    floorIndexById[floor.floorid] = floor.floorIndex
                end
            end)
        end
    end

    local result = {}
    for _, l in ipairs(startLocs or {}) do
        local floorIndex = floorIndexById[l.floor or ""]
        if floorIndex ~= nil then
            result[#result + 1] = core.Loc { x = l.x, y = l.y, floorIndex = floorIndex }
        end
    end
    return result
end

--{ [mapid] = {x1, y1, x2, y2, appliedAt} }: the bounds a map had before an
--encounter's region replaced them. x2/y2 inclusive, the way the
--map.dimensions setter takes them.
local REGION_BOUNDS_DOC = "encounterRegionBounds"

--{ [mapid] = {locs = EncounterStartLoc[], encounterid, name, at} }: the start
--zone of the encounter placed on each map, shown until combat starts there.
local START_ZONE_DOC = "encounterStartZones"

--The map dimensions getter reports x2/y2 one PAST the last tile, while the
--setter takes the last tile itself, so they are converted here.
local function ReadMapBounds(map)
    local dim = map.dimensions
    return { x1 = dim.x1, y1 = dim.y1, x2 = dim.x2 - 1, y2 = dim.y2 - 1 }
end

--MarkUndo first, on the same map object: Upload's undo restores the snapshot
--MarkUndo took, and with none it DELETES the whole map manifest on Ctrl+Z.
local function WriteMapBounds(map, bounds, description)
    map:MarkUndo()
    map.dimensions = { x1 = bounds.x1, y1 = bounds.y1, x2 = bounds.x2, y2 = bounds.y2 }
    map:Upload(description)
end

--Combat is starting on the current map with this encounter (called as the
--initiative queue is created, on the client creating it). Shrinks the map to
--the encounter's region and takes down its start zone and its prep.
--- @param encounter Encounter
function Encounter.OnCombatStarting(encounter)
    local mapid = game.currentMapId
    Encounter.ClearStartZone(mapid)
    Encounter.SetPrep(mapid, nil)
    Encounter.ApplyRegion(encounter)
end

--Shrinks the current map to the encounter's region, keeping the original
--bounds in a shared document so they come back once the encounter is over
--(see RestoreEndedRegionBounds). Done when prep begins and again, harmlessly,
--when combat starts.
--options (all optional):
--  hold: keep the region until Encounter.RestoreRegionBounds is called,
--        rather than restoring it once combat ends. For a caller that owns
--        the map's whole session (Encounter of the Week bounds a game to its
--        encounter's region from arrival on).
--  anyMap: apply it even when the encounter names a different map (the
--        caller knows the encounter belongs to this one).
--- @param encounter Encounter
--- @param options nil|{hold: boolean|nil, anyMap: boolean|nil}
function Encounter.ApplyRegion(encounter, options)
    options = options or {}
    local mapid = game.currentMapId
    local region = encounter:GetRegion()
    local map = game.currentMap
    if region == nil or map == nil then
        return
    end
    if not options.anyMap and encounter.mapid ~= "" and encounter.mapid ~= mapid then
        --the region was drawn on another map.
        return
    end

    local doc = mod:GetDocumentSnapshot(REGION_BOUNDS_DOC)
    doc:BeginChange()
    local saved = doc.data[mapid]
    if saved == nil then
        --a map still shrunk from an earlier encounter (its restore has not
        --run yet) keeps its true original bounds.
        saved = ReadMapBounds(map)
        doc.data[mapid] = saved
    end
    saved.appliedAt = dmhub.serverTime
    if options.hold then
        saved.held = true
    end
    doc:CompleteChange("Encounter region", { undoable = false })

    WriteMapBounds(map, region, "Encounter region")
end

--Puts back the bounds of any map whose combat has ended. Polled by the
--driver below on the host; m_combatSeen keeps a bounds change made the
--moment the queue was created from being undone before the queue lands.
local m_combatSeen = {}
local RESTORE_GRACE_SECONDS = 30

local function RestoreEndedRegionBounds()
    if not dmhub.isDMOrPlayerHost then
        return
    end

    local doc = mod:GetDocumentSnapshot(REGION_BOUNDS_DOC)
    local ended = {}
    for mapid, saved in pairs(doc.data) do
        if type(saved) == "table" then
            local queue = dmhub.GetMapInitiativeQueue(mapid)
            local inCombat = queue ~= nil and not queue.hidden
            if inCombat then
                m_combatSeen[mapid] = true
            elseif saved.held then
                --held by its caller (ApplyRegion's hold) until it calls
                --Encounter.RestoreRegionBounds.
            elseif Encounter.GetPrep(mapid) ~= nil then
                --still preparing the encounter: the region stays until it
                --starts (or the prep is cancelled, which clears the record).
            elseif m_combatSeen[mapid] or dmhub.serverTime - (saved.appliedAt or 0) > RESTORE_GRACE_SECONDS then
                ended[#ended + 1] = mapid
            end
        end
    end

    if #ended == 0 then
        return
    end

    doc:BeginChange()
    for _, mapid in ipairs(ended) do
        local saved = doc.data[mapid]
        local map = game.GetMap(mapid)
        if map ~= nil and saved ~= nil then
            WriteMapBounds(map, saved, "Restore map bounds after encounter")
        end
        doc.data[mapid] = nil
        m_combatSeen[mapid] = nil
    end
    doc:CompleteChange("Restore map bounds after encounter", { undoable = false })
end

--Puts a map's bounds back right away (an encounter prep was cancelled), rather
--than waiting for the restore driver's grace period.
--- @param mapid string
function Encounter.RestoreRegionBounds(mapid)
    local doc = mod:GetDocumentSnapshot(REGION_BOUNDS_DOC)
    local saved = doc.data[mapid]
    if type(saved) ~= "table" then
        return
    end
    local map = game.GetMap(mapid)
    if map ~= nil then
        WriteMapBounds(map, saved, "Restore map bounds")
    end
    doc:BeginChange()
    doc.data[mapid] = nil
    doc:CompleteChange("Restore map bounds", { undoable = false })
    m_combatSeen[mapid] = nil
end

--The encounter has just been placed on the current map for play: show its
--start zone (if it has one) until combat starts.
--- @param encounter Encounter
function Encounter.ShowStartZone(encounter)
    local mapid = game.currentMapId
    local locs = encounter:GetHeroStartLocs()
    if #locs == 0 then
        Encounter.ClearStartZone(mapid)
        return
    end

    local doc = mod:GetDocumentSnapshot(START_ZONE_DOC)
    doc:BeginChange()
    doc.data[mapid] = {
        locs = DeepCopy(locs),
        encounterid = encounter:try_get("id"),
        name = encounter.name,
        at = dmhub.serverTime,
    }
    doc:CompleteChange("Show hero start zone", { undoable = false })
end

--- @param mapid string
--- @param encounterid nil|string only clear it if this encounter's zone is showing.
function Encounter.ClearStartZone(mapid, encounterid)
    local doc = mod:GetDocumentSnapshot(START_ZONE_DOC)
    local entry = doc.data[mapid]
    if entry == nil then
        return
    end
    if encounterid ~= nil and entry.encounterid ~= encounterid then
        return
    end
    doc:BeginChange()
    doc.data[mapid] = nil
    doc:CompleteChange("Clear hero start zone", { undoable = false })
end

-- ===========================================================================
-- Encounter prep: the pre-combat phase
-- ===========================================================================
--
-- An encounter placed for play (Start Encounter, or dragging it onto the
-- board) waits on its map in "prep" until the Director presses Draw Steel:
-- the map is already shrunk to its region, the start zone shows, heroes are
-- brought in, and monsters re-balance as the hero count changes. The runtime
-- and the Director's bar live in Draw Steel V/EncounterPrep.lua; the record
-- lives here, beside the region and start zone it drives, because documents
-- belong to the mod that opens them.

--- @class EncounterPrepRecord
--- @field prepid string unique per prep, so clients can tell one prep on a map from the next.
--- @field encounterid string id in the "encounters" table ("" = not saved there).
--- @field name string
--- @field by string userid of the Director who started it; their client balances.
--- @field startedAt number
--- @field placementids table<string, string> "g<group index>" -> the group's placement id for this play.
--- @field removed table<string, table<string, number>> placement id -> monsterid -> monsters the Director deleted by hand.
--- @field added table<string, boolean> charids of monsters the Director added by hand.
--- @field excluded table<string, boolean> hero charids left out of the fight.
--- @field heroOverride nil|number the hero count to balance for instead of the heroes on the map.

local PREP_DOC = "encounterPrep"

--- @param mapid string|nil
--- @return EncounterPrepRecord|nil
function Encounter.GetPrep(mapid)
    if mapid == nil then
        return nil
    end
    local entry = mod:GetDocumentSnapshot(PREP_DOC).data[mapid]
    if type(entry) ~= "table" then
        return nil
    end
    return entry
end

--The path to monitor (monitorGame) for any change to any map's prep.
--- @return string
function Encounter.PrepDocPath()
    return mod:GetDocumentPath(PREP_DOC)
end

--- @param mapid string
--- @param record EncounterPrepRecord|nil nil ends the prep on that map.
function Encounter.SetPrep(mapid, record)
    local doc = mod:GetDocumentSnapshot(PREP_DOC)
    if record == nil and doc.data[mapid] == nil then
        return
    end
    doc:BeginChange()
    doc.data[mapid] = record
    doc:CompleteChange(cond(record == nil, "End encounter prep", "Encounter prep"), { undoable = false })
end

--Changes a map's prep record in place: fn(record) mutates it. Does nothing
--when the map has no prep.
--- @param mapid string
--- @param description string
--- @param fn fun(record: EncounterPrepRecord)
function Encounter.ModifyPrep(mapid, description, fn)
    local doc = mod:GetDocumentSnapshot(PREP_DOC)
    local record = doc.data[mapid]
    if type(record) ~= "table" then
        return
    end
    doc:BeginChange()
    fn(doc.data[mapid])
    doc:CompleteChange(description, { undoable = false })
end

--This client's view of the current map's start zone: the outline everyone
--sees, and on players' clients the movement confinement. The Director is
--never confined: the restriction applies to every token on a client, and the
--Director has monsters to place.
local START_ZONE_COLOR = "#79d2a0"
local m_startZone = {
    key = nil,
    marker = nil,
    restricted = false,
}

local function ClearStartZoneView()
    if m_startZone.marker ~= nil then
        pcall(function() m_startZone.marker:Destroy() end)
        m_startZone.marker = nil
    end
    if m_startZone.restricted then
        m_startZone.restricted = false
        pcall(function() dmhub.ClearMovementRestriction() end)
    end
    m_startZone.key = nil
end

local function UpdateStartZoneView()
    local mapid = game.currentMapId
    if mapid == nil then
        ClearStartZoneView()
        return
    end
    local entry = mod:GetDocumentSnapshot(START_ZONE_DOC).data[mapid]

    local queue = dmhub.initiativeQueue
    local inCombat = queue ~= nil and not queue.hidden
    if entry ~= nil and inCombat then
        --combat started without passing through OnCombatStarting.
        if dmhub.isDMOrPlayerHost then
            Encounter.ClearStartZone(mapid)
        end
        entry = nil
    end

    if entry == nil or type(entry.locs) ~= "table" or #entry.locs == 0 then
        ClearStartZoneView()
        return
    end

    --rebuilt only when the zone, the map or the floor list changes.
    local floorCount = 0
    pcall(function() floorCount = #game.currentMap.floors end)
    local key = string.format("%s|%s|%s|%d|%s", mapid, tostring(entry.encounterid), tostring(entry.at), floorCount, tostring(dmhub.isDM))
    if key == m_startZone.key then
        return
    end

    ClearStartZoneView()
    m_startZone.key = key

    local locs = Encounter.StartLocsOnCurrentMap(entry.locs)
    if #locs == 0 then
        return
    end

    m_startZone.marker = dmhub.MarkLocs {
        locs = locs,
        color = START_ZONE_COLOR,
        style = "dashed",
    }

    if not dmhub.isDM then
        m_startZone.restricted = true
        pcall(function() dmhub.SetMovementRestriction { locs = locs } end)
    end
end

--The per-client driver: a cheap poll that self-heals across reloads, map
--changes and combats ended from anywhere.
dmhub.Coroutine(function()
    while true do
        coroutine.yield(0.5)
        if mod.unloaded then
            ClearStartZoneView()
            return
        end
        pcall(function()
            if game.currentMap ~= nil then
                pcall(UpdateStartZoneView)
                pcall(RestoreEndedRegionBounds)
            end
        end)
    end
end)

-- The engine's own click-to-place is armed through GUI focus, not through a
-- mode flag: dmhub.GetSelectedEncounter reads gui.GetFocus().data.encounter,
-- so while a panel carrying an encounter holds focus the map draws a ghost of
-- the whole roster under the cursor and the next map click spawns it. Nothing
-- disarms that on its own. Once the encounter has been placed some other way
-- -- or combat has begun -- the arming is stale: the Director is left dragging
-- a phantom copy of the encounter around, one click from spawning a second
-- one on top of the fight they just started.
--
-- Only a panel that is actually arming an encounter is cleared, never the
-- placement banner, which holds focus on purpose so it can receive the map
-- click. The clear is repeated a beat later because the click that placed the
-- encounter can still be bubbling: the encounter card's own click handler
-- re-focuses the card AFTER this runs.
function Encounter.DisarmClickToPlace()
    local function Clear()
        local focus = gui.GetFocus()
        if focus == nil or not focus.valid then
            return
        end
        if focus:HasClass("encounterPlacementBanner") then
            return
        end
        if focus.data.encounter ~= nil then
            gui.SetFocus(nil)
        end
    end

    Clear()
    dmhub.Schedule(0.1, function()
        if mod.unloaded then
            return
        end
        Clear()
    end)
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
    --spawned reinforcement tokenids, for the monster-group onset snapshot below.
    local spawnedTokenIds = {}
    --the same tokens tagged with the slot they arrived in, so saved mounts among
    --the reinforcements are re-seated once the whole wave is down. A rider whose
    --mount was placed up front (not part of this wave) is left standing.
    local mountEntries = {}

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
                    --a grid loc has no altitude of its own: the engine stands
                    --it on the ground (down into a pit as well as up a cliff).
                    local onGround = false
                    if loc ~= nil then
                        if not loc.isValidFloor then
                            loc = loc.withCurrentFloor
                        end
                    else
                        local col = fallbackIndex % 5
                        local row = math.floor(fallbackIndex / 5)
                        loc = core.Loc { x = baseX + col, y = baseY + row, floorIndex = floorIndex }
                        onGround = true
                    end
                    spawnIndex = spawnIndex + 1
                    fallbackIndex = fallbackIndex + 1

                    local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true, onGround = onGround })
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
                        if (group.startsHidden or {})[slot] then
                            token.properties:BecomeHidden(token)
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
                        spawnedTokenIds[#spawnedTokenIds+1] = token.charid
                        mountEntries[#mountEntries+1] = {
                            group = groupIndex,
                            slot = slot,
                            token = token,
                        }
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

    --put reinforcements that were saved riding each other back in the saddle.
    self:RestoreMounts(mountEntries)

    --extend the monster-group onset snapshot with the freshly arrived groups, so
    --reinforcements get their own card (and stat attribution) on the victory
    --screen's Monsters tab. Rides the same queue upload the caller performs
    --after MarkWaveDeployed.
    if #spawnedTokenIds > 0 then
        self:RecordOnsetMonsterGroups(spawnedTokenIds)
    end

    self:MarkWaveDeployed(waveid)
    return spawnedCount
end

-- Count the reinforcement monsters that have NOT yet been deployed (their wave is
-- not in deployedWaves). These are monsters that "will arrive" -- they count toward
-- the monsters the heroes still have to deal with even though they're not yet on
-- the map. Each minion squad counts as one monster.
-- If org is given (a lowercase organization keyword such as "leader"), only pending
-- non-minion monsters of that organization are counted; org "*" counts every
-- pending non-minion and no minion squads.
function LiveEncounter:CountPendingReinforcements(numHeroes, org)
    numHeroes = numHeroes or dmhub.GetSettingValue("numheroes")
    local clone = self:CloneForNumberOfHeroes(numHeroes)
    local count = 0
    for _, group in ipairs(clone.groups) do
        if group.wave ~= nil and not self:IsWaveDeployed(group.wave) then
            for monsterid, quantity in pairs(group.monsters) do
                local monster = assets.monsters[monsterid]
                if monster ~= nil and not monster.properties.minion and
                    (org == nil or org == "*" or OrganizationKeyword(monster.properties) == org) then
                    count = count + quantity
                end
            end
            if org == nil then
                count = count + Encounter.GroupMinionSquadCount(group)
            end
        end
    end
    return count
end

-- Walk the active initiative queue and count the live combatants on each side:
--   heroes  : hero/player tokens with Stamina (hitpoints) > 0
--   monsters: non-minion monster tokens with Stamina > 0, plus one for each minion
--             squad that still has a minion standing
-- Returns heroes, monsters.
function LiveEncounter:CountLiveCombatants()
    local q = dmhub.initiativeQueue
    local heroes, monsters = 0, 0
    if q == nil then
        return heroes, monsters
    end

    local seen = {}
    local countedUnits = {}
    for initiativeid, _ in pairs(q.entries) do
        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        for _, token in ipairs(tokens or {}) do
            if token ~= nil and not seen[token.charid] then
                seen[token.charid] = true
                local props = token.properties
                if props ~= nil then
                    if props:IsHero() then
                        if props:CurrentHitpoints() > 0 then
                            heroes = heroes + 1
                        end
                    else
                        --a minion's Stamina is the whole squad's, so ask
                        --whether this minion is dead instead.
                        local standing
                        if props.minion then
                            standing = not props:IsDead()
                        else
                            standing = props:CurrentHitpoints() > 0
                        end
                        local unit = Encounter.VictoryUnitKey(token)
                        if standing and unit ~= nil and not countedUnits[unit] then
                            countedUnits[unit] = true
                            monsters = monsters + 1
                        end
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
    return self:CountLiveNonMinions("leader")
end

-- Counts the live (Stamina > 0) non-minion monsters in the active initiative queue,
-- only those of organization org (a lowercase keyword such as "leader") when given.
-- Drives "Leader Defeated" and "All Non-Minions Defeated".
function LiveEncounter:CountLiveNonMinions(org)
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
                if props ~= nil and props:IsMonster() and not props.minion and not Encounter.IsHeroSideSummon(token) and
                    (org == nil or OrganizationKeyword(props) == org) and props:CurrentHitpoints() > 0 then
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
--   * the victory condition is "all monsters defeated" (or "all non-minions defeated")
--     AND the encounter contains exactly one non-minion monster with the Solo role, or
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

    if condition ~= "solo_exhausted" and condition ~= "all_defeated" and condition ~= "nonminions_defeated" then
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

    --all_defeated / nonminions_defeated: only surface a boss bar for a single-solo encounter.
    if #solos == 1 then
        return solos[1]
    end

    return nil
end

-- Returns true when this encounter's configured victory condition has been met.
-- Each minion squad counts as one monster. "Monsters remaining" = live monsters on the
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

    --an encounter with no non-minions at all is judged as "All Monsters Defeated", so
    --it can never be won before a blow is struck.
    if condition == "nonminions_defeated" and self:try_get("onsetNonMinionCount", 0) <= 0 then
        condition = "all_defeated"
    end

    if condition == "all_defeated" then
        return monstersRemaining <= 0
    elseif condition == "nonminions_defeated" then
        return self:CountLiveNonMinions() + self:CountPendingReinforcements(numHeroes, "*") <= 0
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
--   defeated : how many monsters (minion squads count as one) have been defeated so far
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

    --"All Non-Minions Defeated" counts non-minions only; minion squads are ignored.
    if condition == "nonminions_defeated" and self:try_get("onsetNonMinionCount", 0) > 0 then
        local remaining = self:CountLiveNonMinions() + self:CountPendingReinforcements(numHeroes, "*")
        --the Director may have added non-minions during prep, so never report fewer
        --needed than are still standing.
        local needed = math.max(self:try_get("onsetNonMinionCount", 0), remaining)
        return needed - remaining, needed
    end
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
    if condition == "nonminions_defeated" and self:try_get("onsetNonMinionCount", 0) > 0 then
        return string.format("Objective: Defeat %d/%d non-minions to win", defeated, needed)
    end
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
        lines[#lines + 1] = "Victory when every monster is defeated. Each minion squad counts as one monster."
    elseif condition == "nonminions_defeated" then
        local tooltipLines = {
            "Victory when every monster that is not a minion is defeated. Minions left standing do not count.",
            "",
            string.format("Non-minions at onset: %d", self:try_get("onsetNonMinionCount", 0)),
            string.format("Non-minions still standing: %d", self:CountLiveNonMinions()),
        }
        local pendingNonMinions = self:CountPendingReinforcements(numHeroes, "*")
        if pendingNonMinions > 0 then
            tooltipLines[#tooltipLines + 1] = string.format("Non-minions still to arrive: %d", pendingNonMinions)
        end
        if self:try_get("onsetNonMinionCount", 0) <= 0 then
            tooltipLines[#tooltipLines + 1] = "This encounter has no non-minions, so every monster must be defeated."
        end
        return table.concat(tooltipLines, "\n")
    elseif condition == "half_defeated" then
        lines[#lines + 1] = "Victory when at least half of the encounter's monsters are defeated. Each minion squad counts as one monster."
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
    lines[#lines + 1] = string.format("Total monsters (each minion squad counts as one): %d", onset)
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
--`hostAccess` (optional): search the journal with HOSTING-level access rather
--than the viewer's. A directorless game's host has dmhub.isDM false, so the
--map's own journal folder -- where the encounter lives -- is not in their
--accessible roots; setup code that must find the encounter to run it passes
--this. Director-facing UI does not.

--Does the document store any RichEncounter annotation at all? Parsing a
--document (GetReferencedAnnotations) is expensive -- it runs every `???`
--query line -- and only RichEncounter annotations can contribute, so a
--document without one is skipped unparsed. Most journals hold ~100 such docs.
local function HasEncounterAnnotation(markdownDoc)
    local annotations = markdownDoc:try_get("annotations")
    if annotations == nil then
        return false
    end
    for _, annotation in pairs(annotations) do
        if type(annotation) == "table" and annotation.typeName == "RichEncounter" then
            return true
        end
    end
    return false
end

--DIAG (HarvestBurst): GetEncountersOnCurrentMap walks the whole journal, so a
--caller running it every frame or two made the map stutter during the Draw
--Steel banner (2026-10-18 playtest, caller never identified). Logs who calls it
--when it runs more than HARVEST_BURST_CALLS times in HARVEST_BURST_WINDOW
--seconds, at most once per HARVEST_BURST_LOG_GAP seconds.
local HARVEST_BURST_CALLS = 4
local HARVEST_BURST_WINDOW = 2
local HARVEST_BURST_LOG_GAP = 10
local g_harvestCallTimes = {}
local g_harvestLastBurstLog = -1000

local function NoteHarvestCall(elapsedMs, parsedDocs)
    local now = dmhub.Time()
    local recent = {}
    for _, t in ipairs(g_harvestCallTimes) do
        if now - t < HARVEST_BURST_WINDOW then
            recent[#recent + 1] = t
        end
    end
    recent[#recent + 1] = now
    g_harvestCallTimes = recent
    if #recent > HARVEST_BURST_CALLS and now - g_harvestLastBurstLog > HARVEST_BURST_LOG_GAP then
        g_harvestLastBurstLog = now
        printf("PERF:: Encounter.GetEncountersOnCurrentMap called %d times in %ds (last %.1f ms, %d docs parsed); caller:\n%s",
            #recent, HARVEST_BURST_WINDOW, elapsedMs, parsedDocs, debug.traceback("", 3))
    end
end

function Encounter.GetEncountersOnCurrentMap(hostAccess)
    local startTime = os.clock()
    local parsedDocs = 0
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

        if not HasEncounterAnnotation(markdownDoc) then
            return
        end
        parsedDocs = parsedDocs + 1

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
        local accessibleRoots = CustomDocument.GetAccessibleRoots(hostAccess)
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

    NoteHarvestCall((os.clock() - startTime)*1000, parsedDocs)
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
--       onReset = function(ctx) end,  -- an authoring test reset: undo what the script changed on the map
--   }
--
-- victory replaces the encounter's built-in victory-condition dropdown; defeat
-- is script-only (the base game has no built-in defeat conditions). When a
-- defeat check passes, the director's initiative bar offers "Declare Defeat",
-- which announces the outcome and shows the full-screen DEFEAT screen (the
-- defeatAwarded flag; combat ends when the director presses Proceed there).
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

--- @class EncounterScript: GameType
--- @field new fun(o?: table): EncounterScript
--- @field id string Key of this row in its data table; SetAndUploadTableItem sets it.
--- @field name string Display name of the library script.
--- @field description string What the script does, shown in pickers and the compendium.
--- @field code string The Lua source; must return a definition table.
--- @field guid string Stable id; OnDeserialize generates one if missing.
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
-- onPrepare runs once when the encounter is placed for play and waits for
-- Draw Steel (its pre-combat prep), on the Director's client that placed it:
-- ctx.queue is nil, ctx.round is 0 and ctx.state is not kept.
--
-- ctx methods (call with ':'):
--   ctx:Announce(text)      send a chat message
--   ctx:Banner(text, subtitle, bannerType)  show everyone a full-screen dramatic
--                               banner; bannerType "malice" for the lighter one
--   ctx:SetWaterLevel(level)    set the map water level (multiples of 0.5; nil
--                               removes it); creatures float up/settle with it
--   ctx:GetWaterLevel()     the map water level, or nil
--   ctx:DeployWave(waveid)  deploy one of the encounter's reinforcement waves
--   ctx:SetVictories(n)     change how many Victories winning is worth (the
--                               builder's "Victories awarded"); set it before
--                               the victory condition is met
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
    -- announces the outcome and shows the full-screen defeat screen:
    -- defeat = {
    --     text = function(ctx) return "The Caravan is Destroyed" end,
    --     check = function(ctx) return ctx.state.caravanDestroyed == true end,
    -- },

    -- Uncomment to show a rule or countdown to everyone under the objective
    -- on the initiative bar. Runs on the host each heartbeat while combat is
    -- live; return nil to show nothing, one entry, or a list of entries.
    -- timer (optional) draws a segmented clock: remaining of total segments lit,
    -- spent ones darkening clockwise from twelve; color is an optional "#rrggbb".
    -- status = function(ctx)
    --     return {
    --         title = "Collapsing Ceiling",
    --         tooltip = "The ceiling falls in 2 rounds.",
    --         timer = { remaining = 2, total = 3 },
    --     }
    -- end,

    onPrepare = function(ctx)
    end,

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

    if def.status ~= nil and type(def.status) ~= "function" then
        return nil, "status must be a function"
    end
    norm.status = def.status

    for _, handler in ipairs({ "onPrepare", "onStart", "onRound", "think", "onEnd", "onReset" }) do
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
--- @return table|nil definition
--- @return string|nil error
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
    if def.status ~= nil then
        parts[#parts + 1] = "initiative bar status"
    end
    local handlers = {}
    for _, handler in ipairs({ "onPrepare", "onStart", "onRound", "think", "onEnd", "onReset" }) do
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

--- @class EncounterScriptInstance: GameType
--- @field new fun(o?: table): EncounterScriptInstance
--- @field scriptid string Id into the encounterScripts table or a "builtin:" id; "" = inline custom code.
--- @field code string Inline Lua source (custom scripts only).
--- @field name string Cached display name, refreshed from the definition at edit time.
--- @field params table {paramid = value} chosen by the director.
--- @field victoryText string|nil Cached resolved victory text (edit-time snapshot; what players see).
--- @field defeatText string|nil Cached resolved defeat text (edit-time snapshot; what players see).
--- @field guid string Unique id of this attached script; OnDeserialize fills it in when missing.
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
--- @return table|nil definition
--- @return string|nil error
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
--- @return string|nil text
--- @return table|nil instance
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
--- @return string|nil text
--- @return table|nil instance
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

--- Every status entry the attached scripts' status functions last returned,
--- in script order, for the initiative bar. These are the strings and numbers
--- the host resolved and networked, so any client can read them.
--- @return {title: string, tooltip: string|nil, timer: {remaining: number, total: number, color: string|nil}|nil}[]
function LiveEncounter:GetScriptStatus()
    local result = {}
    for _, instance in ipairs(self:try_get("scripts", {})) do
        local st = self:GetScriptState(instance:try_get("guid", ""))
        if st ~= nil and type(st.status) == "table" then
            for _, entry in ipairs(st.status) do
                if type(entry) == "table" and type(entry.title) == "string" then
                    result[#result + 1] = entry
                end
            end
        end
    end
    return result
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
    ctx.SetWaterLevel = NotAllowed
    ctx.GetWaterLevel = function(_) return Encounter.GetWaterLevel() end
    ctx.DeployWave = NotAllowed
    ctx.SetVictories = NotAllowed
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
    --hosting capability: the EotW player host must be electable.
    if not IsDMOrPlayerHost() then
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

--Shared with other host-only round work (EnvironmentalKeyword's end-of-round
--zone spread) so every such job elects the same client.
LiveEncounter.IsElectedHost = IsElectedHost

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

    --the full-screen DramaticBanner; it is a shared document, so everyone sees it.
    --bannerType is a DramaticBanner.types id ("heroic" swords, the default, or "malice").
    ctx.Banner = function(_, text, subtitle, bannerType)
        local banner = rawget(_G, "DramaticBanner")
        if banner ~= nil then
            pcall(function() banner.Show{ text = tostring(text), subtitle = subtitle, bannerType = bannerType } end)
        end
    end

    ctx.Log = function(_, text)
        print(string.format("EncounterScript '%s': %s", instance:try_get("name", "script"), tostring(text)))
    end

    --The map water level: creatures float up with rising water and settle with
    --falling water on their own (the engine moves them). nil removes the water.
    ctx.SetWaterLevel = function(_, level, options)
        local ok, err = Encounter.SetWaterLevel(level, options)
        if not ok then
            print(string.format("EncounterScript '%s': SetWaterLevel: %s", instance:try_get("name", "script"), tostring(err)))
        end
        return ok
    end

    ctx.GetWaterLevel = function(_)
        return Encounter.GetWaterLevel()
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

    --The award reads live.victories after the victory screen shows, so a script must set it before winning.
    ctx.SetVictories = function(_, amount)
        local victories = tonumber(amount)
        if victories == nil then
            return false
        end
        victories = math.max(0, math.floor(victories))
        local queue = dmhub.initiativeQueue
        if queue == nil or queue.hidden then
            return false
        end
        local liveEncounter = queue:try_get("liveEncounter")
        if type(liveEncounter) ~= "table" then
            return false
        end
        if liveEncounter:try_get("victories", 1) == victories then
            return true
        end
        liveEncounter.victories = victories
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

--Loads an encounter's scripts as it goes into prep: compiles each one, and
--when runHandlers is set fires its onPrepare once. Returns a summary per
--script for the prep bar: { name, error, victoryText, defeatText }.
--- @param encounter Encounter
--- @param runHandlers boolean
--- @return {name: string, error: nil|string, victoryText: nil|string, defeatText: nil|string}[]
function EncounterScript.PrepareEncounter(encounter, runHandlers)
    local result = {}
    for _, instance in ipairs(encounter:try_get("scripts", {})) do
        local entry = { name = instance:try_get("name", "Encounter Script") }
        local def, err = instance:GetDefinition()
        if def == nil then
            entry.error = err or "The script did not compile"
            PrintScriptError(instance, entry.error)
        else
            if def.name ~= nil then
                entry.name = def.name
            end
            local ctx = {
                params = instance:ResolveParams(def),
                state = {},
                round = 0,
                queue = nil,
                encounter = encounter,
                isHost = true,
            }
            ctx.IsLive = function()
                return not mod.unloaded and Encounter.GetPrep(game.currentMapId) ~= nil
            end
            ctx.Announce = function(_, text)
                pcall(function() chat.Send(tostring(text)) end)
            end
            ctx.Log = function(_, text)
                print(string.format("EncounterScript '%s': %s", entry.name, tostring(text)))
            end
            entry.victoryText = ResolveLiveConditionText(def.victory, ctx) or instance:try_get("victoryText")
            entry.defeatText = ResolveLiveConditionText(def.defeat, ctx) or instance:try_get("defeatText")
            if runHandlers and def.onPrepare ~= nil then
                local ok, fnErr = pcall(def.onPrepare, ctx)
                if not ok then
                    entry.error = tostring(fnErr)
                    PrintScriptError(instance, entry.error)
                end
            end
        end
        result[#result + 1] = entry
    end
    return result
end

--- Runs every onReset handler of an encounter's scripts: an authoring test
--- reset (EncounterMontage.ResetTest) asks each script to put back what it
--- changed on the map, since the next combat's onStart may be a while off.
--- Called outside combat, so ctx.queue is nil and ctx.state is a fresh table.
--- @param encounter Encounter
function EncounterScript.ResetEncounter(encounter)
    for _, instance in ipairs(encounter:try_get("scripts", {})) do
        local def = instance:GetDefinition()
        if def ~= nil and def.onReset ~= nil then
            local name = def.name or instance:try_get("name", "Encounter Script")
            local ctx = {
                params = instance:ResolveParams(def),
                state = {},
                round = 0,
                queue = nil,
                encounter = encounter,
                isHost = true,
            }
            ctx.Log = function(_, text)
                print(string.format("EncounterScript '%s': %s", name, tostring(text)))
            end
            --putting the water back is what onReset is for (Rising Waters drains).
            ctx.SetWaterLevel = function(_, level, options)
                local setOk, setErr = Encounter.SetWaterLevel(level, options)
                if not setOk then
                    print(string.format("EncounterScript '%s': SetWaterLevel: %s", name, tostring(setErr)))
                end
                return setOk
            end
            ctx.GetWaterLevel = function(_)
                return Encounter.GetWaterLevel()
            end
            local ok, err = pcall(def.onReset, ctx)
            if not ok then
                PrintScriptError(instance, tostring(err))
            end
        end
    end
end

--Run a script's status function against the live host ctx and copy out only
--the fields the initiative bar draws, so the networked state stays small and
--plain. Returns a list of { title, tooltip, timer = { remaining, total, color } }
--(possibly empty), or nil when the function errored.
local function ResolveLiveStatus(instance, def, ctx)
    if def.status == nil then
        return {}
    end
    local ok, result = pcall(def.status, ctx)
    if not ok then
        PrintScriptError(instance, "status error: " .. tostring(result))
        return nil
    end
    if type(result) ~= "table" then
        return {}
    end
    --a single entry is the common case; accept it without a wrapping list.
    if result.title ~= nil or result.tooltip ~= nil or result.timer ~= nil then
        result = { result }
    end
    local list = {}
    for _, entry in ipairs(result) do
        if type(entry) == "table" and type(entry.title) == "string" and entry.title ~= "" then
            local item = { title = entry.title }
            if type(entry.tooltip) == "string" and entry.tooltip ~= "" then
                item.tooltip = entry.tooltip
            end
            local timer = entry.timer
            if type(timer) == "table" and type(timer.total) == "number" and timer.total >= 1 then
                local total = math.min(24, math.floor(timer.total))
                local remaining = math.max(0, math.min(total, math.floor(tonumber(timer.remaining) or 0)))
                item.timer = { remaining = remaining, total = total }
                if type(timer.color) == "string" and timer.color:match("^#%x%x%x%x%x%x$") then
                    item.timer.color = timer.color
                end
            end
            list[#list + 1] = item
        end
    end
    return list
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
    local ok, json = pcall(dmhub.ToJson, st)
    --nil when the state could not be serialized.
    local before = ok and json or nil

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
        --an erroring status keeps showing the last good one.
        st.status = ResolveLiveStatus(instance, def, ctx) or st.status
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
--  getText      : function() -> current code
--  setText      : function(newCode) called whenever the code changes
--  compile      : function(code) -> def, err (default CompileDefinition; lets
--                 other script kinds, e.g. Map Scripts, reuse this widget)
--  describe     : function(def) -> status string (default DescribeDefinition)
function EncounterScript.CreateCodePanel(options)
    options = options or {}
    local compile = options.compile or EncounterScript.CompileDefinition
    local describe = options.describe or EncounterScript.DescribeDefinition

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
            local def, err = compile(code)
            if def == nil then
                element.text = tostring(err)
            else
                element.text = describe(def)
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
                watcher = dmhub.OpenTextFileInConnectedEditor(options.getText() or "", function(contents)
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
--  onSave           : function(newCode) - called when Save is pressed
--  canSaveToLibrary : offer the "Save to Library..." button
--  onSavedToLibrary : function(scriptid) - called after the library item is
--                     created (the dialog closes afterwards)
--  compile/describe : as CreateCodePanel - reuse by other script kinds
--  saveToLibrary    : function(def, code) -> scriptid; overrides the default
--                     create-an-EncounterScript library save
function EncounterScript.ShowCodeEditorDialog(options)
    options = options or {}
    local currentCode = options.code or ""
    local compile = options.compile or EncounterScript.CompileDefinition

    local codePanel = EncounterScript.CreateCodePanel{
        width = "100%",
        height = 380,
        compile = options.compile,
        describe = options.describe,
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
                local def, err = compile(currentCode)
                if def == nil then
                    gui.ModalMessage{
                        title = "Cannot save to library",
                        message = tostring(err),
                    }
                    return
                end
                local scriptid
                if options.saveToLibrary ~= nil then
                    scriptid = options.saveToLibrary(def, currentCode)
                else
                    local item = EncounterScript.new{
                        guid = dmhub.GenerateGuid(),
                        name = def.name or "New Encounter Script",
                        description = def.description or "",
                        code = currentCode,
                    }
                    scriptid = dmhub.SetAndUploadTableItem(EncounterScript.tableName, item)
                end
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

EncounterScript.RegisterBuiltin{
    id = "builtin:rising-waters",
    name = "Rising Waters",
    description = "Every few turns the map's water level rises, flooding lower ground: creatures float up with it, deep water is swum, and the new shoreline becomes shallow water.",
    code = [==[
return {
    name = "Rising Waters",
    description = "Every few turns the map's water level rises. Combat starts with the water at the Starting Level; each rise lifts it by Rise Amount squares. Ground 1 square or more under the water is deep water (swimming), less is shallow water (difficult terrain for creatures without a swim speed). Creatures float up with the water. Set how the water looks in Map Settings > Water.",

    params = {
        { id = "startLevel", name = "Starting Level", type = "number", default = 0, min = -20, max = 20 },
        { id = "riseAmount", name = "Rise Amount (squares)", type = "number", default = 1, min = 0.5, max = 5 },
        { id = "turnsPerRise", name = "Turns Between Rises", type = "number", default = 3, min = 1, max = 20 },
        { id = "rises", name = "Number of Rises", type = "number", default = 2, min = 1, max = 10 },
        { id = "announce", name = "Announce in Chat", type = "boolean", default = true },
        { id = "banner", name = "Show a Banner", type = "boolean", default = true },
    },

    --start at the starting level, so a replayed encounter does not start already flooded.
    onStart = function(ctx)
        ctx.state.rises = 0
        ctx:SetWaterLevel(ctx.params.startLevel)
    end,

    --a test reset drains the water back to its starting level.
    onReset = function(ctx)
        ctx:SetWaterLevel(ctx.params.startLevel)
    end,

    --counts turns (not rounds) by watching the current turn's id change; the
    --water rises as the turn after every turnsPerRise-th completed turn begins.
    think = function(ctx)
        local st = ctx.state
        st.rises = st.rises or 0
        if st.rises >= ctx.params.rises or ctx.queue == nil then
            return
        end
        if ctx.queue:CurrentInitiativeId() == nil then
            return
        end
        local turnid = ctx.queue:GetTurnId()
        if turnid == nil or turnid == st.lastTurnId then
            return
        end
        st.lastTurnId = turnid
        st.turnsStarted = (st.turnsStarted or 0) + 1

        local completed = st.turnsStarted - 1
        local rises = math.min(ctx.params.rises, math.floor(completed / ctx.params.turnsPerRise))
        if rises <= st.rises then
            return
        end
        st.rises = rises

        ctx:SetWaterLevel(ctx.params.startLevel + rises * ctx.params.riseAmount)

        local amount = ctx.params.riseAmount
        local squares = (amount == 1) and "1 square" or string.format("%g squares", amount)
        if ctx.params.announce then
            ctx:Announce(string.format("The water rises by %s! (%d of %d)", squares, rises, ctx.params.rises))
        end
        if ctx.params.banner then
            ctx:Banner("Rising Waters", string.format("The waters have risen by %s!", squares), "malice")
        end
    end,

    --the initiative bar's countdown: one pie segment per turn left before the
    --next rise, using the same turn count as think.
    status = function(ctx)
        local st = ctx.state
        local per = ctx.params.turnsPerRise
        local risesLeft = ctx.params.rises - (st.rises or 0)
        if risesLeft <= 0 then
            return { title = "Rising Waters", tooltip = "The water has risen as high as it will go." }
        end
        local completed = math.max(0, (st.turnsStarted or 0) - 1)
        local remaining = math.max(1, math.min(per, ((st.rises or 0) + 1) * per - completed))
        local tooltip = string.format("The water will rise in %d turns", remaining)
        if remaining == 1 then
            tooltip = "The water will rise at the start of the next turn"
        end
        return {
            title = "Rising Waters",
            tooltip = tooltip,
            timer = { remaining = remaining, total = per, color = "#62b6ff" },
        }
    end,
}
]==],
}
