local mod = dmhub.GetModLoading()

-- ===========================================================================
-- Encounter prep: the pre-combat phase on the map
-- ===========================================================================
--
-- Start Encounter (the list card, the builder) and dragging an encounter onto
-- the board place it on its map and put it into prep instead of opening the
-- Prepare Combat dialog. While it is in prep:
--
--   * the map is shrunk to the encounter's region and the start zone shows
--     (Encounter.ApplyRegion / Encounter.ShowStartZone, MCDMEncounter.lua);
--   * its scripts are compiled and their onPrepare handlers run once;
--   * the Director gets a bar at the top of the map showing the two sides,
--     the party's heroes who are not on the map yet (one click summons them
--     into the start zone), and the hero count the monsters are balanced for;
--   * the monsters re-balance as heroes come and go, following the plan's
--     balancing (per-monster deltas, "appears at N+ heroes" gates, stamina);
--   * monsters the Director deletes stay deleted, and monsters added to the
--     map (from the bestiary, say) join the encounter -- for this play only,
--     the saved plan is not changed.
--
-- Draw Steel on the bar starts combat with exactly the tokens in the prep;
-- Configure Initiative opens the Prepare Combat dialog for the odd fight that
-- needs it. Combat starting clears the prep (Encounter.OnCombatStarting).
--
-- The prep record is the shared document in MCDMEncounter.lua (Encounter.GetPrep
-- and friends). Only the Director who started the prep balances it (record.by),
-- so two Directors never spawn the same monster twice. Players see only the
-- start zone; the bar is the Director's.

--Seconds between balancing passes; and how long to wait after spawning or
--deleting before the next, so the map catches up first.
local TICK_SECONDS = 0.5
local SETTLE_SECONDS = 1.0

--The largest party balancing goes up to.
local MAX_HEROES = 10

--- @class EncounterPrepLocal
--- @field prepid string|nil the prep this state belongs to.
--- @field encounter Encounter|nil the play copy of the plan.
--- @field tracked table<string, string> charid -> "pid|monsterid" of the plan's monsters seen on the map.
--- @field removedIds table<string, string> charid -> key of monsters counted as deleted by hand (an undo brings them back).
--- @field ourDeletes table<string, boolean> charids the balancer itself deleted.
--- @field known table<string, boolean> every charid seen on the map since the prep began.
--- @field lastBalance number|nil the hero count stamina was last set for.
--- @field settleUntil number
--- @field scripts table[]|nil the scripts summary for the bar.

--Per map, this client's working state for a prep.
--- @type table<string, EncounterPrepLocal>
local m_local = {}

--The play copies of plans started on this client, by map: the copy carries
--the placement ids for this play. Used before the shared record lands, and
--for plans that are not saved in the encounters table.
--- @type table<string, {prepid: string, encounter: Encounter}>
local m_playCopies = {}

local function Key(pid, monsterid)
    return pid .. "|" .. monsterid
end

--- @param mapid string
--- @param record EncounterPrepRecord
--- @return EncounterPrepLocal
local function LocalState(mapid, record)
    local state = m_local[mapid]
    if state == nil or state.prepid ~= record.prepid then
        state = {
            prepid = record.prepid,
            encounter = nil,
            tracked = {},
            removedIds = {},
            ourDeletes = {},
            known = {},
            lastBalance = nil,
            settleUntil = 0,
            scripts = nil,
        }
        m_local[mapid] = state
    end
    return state
end

--The plan being played in a prep: this client's own copy if it started it,
--else the saved plan with the record's placement ids put back on.
--- @param mapid string
--- @param record EncounterPrepRecord
--- @return Encounter|nil
local function PlayEncounter(mapid, record)
    local state = LocalState(mapid, record)
    if state.encounter ~= nil then
        return state.encounter
    end

    local copy = m_playCopies[mapid]
    if copy ~= nil and copy.prepid == record.prepid then
        state.encounter = copy.encounter
        return state.encounter
    end

    local saved = nil
    if record.encounterid ~= nil and record.encounterid ~= "" then
        saved = dmhub.GetTable("encounters")[record.encounterid]
    end
    if saved == nil then
        return nil
    end
    local encounter = DeepCopy(saved)
    for groupIndex, group in ipairs(encounter.groups) do
        local pid = (record.placementids or {})["g" .. groupIndex]
        if pid ~= nil then
            group.placementid = pid
            group.sourceEncounterId = record.encounterid
        end
    end
    state.encounter = encounter
    return encounter
end

local function TryGet(props, key)
    local value = nil
    pcall(function() value = props:try_get(key) end)
    return value
end

local function IsMonsterToken(tok)
    local result = false
    pcall(function() result = tok.properties:IsMonster() == true end)
    return result
end

local function IsHeroToken(tok)
    local result = false
    pcall(function() result = tok.properties:IsHero() == true end)
    return result
end

--Whether a token fights on the heroes' side: in the party or an allied
--party, or controlled by a player (the same test the combat setup uses).
local function IsPlayerSide(tok)
    if tok.playerControlled then
        return true
    end
    local partyid = tok.partyId
    if partyid == nil then
        return false
    end
    local playerPartyId = GetDefaultPartyID()
    if partyid == playerPartyId then
        return true
    end
    local party = GetParty(playerPartyId)
    return party ~= nil and party:GetAllyParties()[partyid] ~= nil
end

--The placement ids of the plan's start groups, as a set.
--- @param encounter Encounter|nil
--- @return table<string, boolean>
local function PlacementIdSet(encounter)
    local result = {}
    if encounter == nil then
        return result
    end
    for _, group in ipairs(encounter.groups) do
        if group.wave == nil and group.placementid ~= nil then
            result[group.placementid] = true
        end
    end
    return result
end

--The monsters in the prep: the plan's (by placement id) and the ones added
--by hand. byKey groups the plan's by group and monster type, in slot order.
--- @param record EncounterPrepRecord
--- @param encounter Encounter|nil
--- @param ignore table<string, boolean>|nil charids being deleted.
--- @return CharacterToken[] all
--- @return table<string, CharacterToken[]> byKey "pid|monsterid" -> tokens
--- @return table<string, CharacterToken[]> byGroup pid -> tokens
local function PrepMonsters(record, encounter, ignore)
    local pids = PlacementIdSet(encounter)
    local all = {}
    local byKey = {}
    local byGroup = {}
    ignore = ignore or {}
    for _, tok in ipairs(dmhub.allTokens) do
        if not ignore[tok.charid] and tok.properties ~= nil then
            local pid = TryGet(tok.properties, "encounterPlacementId")
            if pid ~= nil and pids[pid] and TryGet(tok.properties, "encounterStaged") == false then
                all[#all + 1] = tok
                local monsterid = TryGet(tok.properties, "encounterSpawnMonster") or ""
                local key = Key(pid, monsterid)
                byKey[key] = byKey[key] or {}
                table.insert(byKey[key], tok)
                byGroup[pid] = byGroup[pid] or {}
                table.insert(byGroup[pid], tok)
            elseif (record.added or {})[tok.charid] then
                all[#all + 1] = tok
            end
        end
    end
    for _, list in pairs(byKey) do
        table.sort(list, function(a, b)
            return (TryGet(a.properties, "encounterSpawnSlot") or 0) < (TryGet(b.properties, "encounterSpawnSlot") or 0)
        end)
    end
    return all, byKey, byGroup
end

--The heroes' side on the map: heroes (who count for balancing) and allies,
--leaving out anyone the Director took out of the fight.
--- @param record EncounterPrepRecord
--- @return CharacterToken[] heroes
--- @return CharacterToken[] allies
--- @return CharacterToken[] excluded
local function PrepHeroes(record)
    local heroes = {}
    local allies = {}
    local excluded = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.properties ~= nil and IsPlayerSide(tok) then
            if (record.excluded or {})[tok.charid] then
                excluded[#excluded + 1] = tok
            elseif IsHeroToken(tok) then
                heroes[#heroes + 1] = tok
            else
                allies[#allies + 1] = tok
            end
        end
    end
    local byName = function(a, b) return (a.name or "") < (b.name or "") end
    table.sort(heroes, byName)
    table.sort(allies, byName)
    return heroes, allies, excluded
end

--The party's heroes who are not on this map.
--- @return CharacterToken[]
local function MissingHeroes()
    local onMap = {}
    for _, tok in ipairs(dmhub.allTokens) do
        onMap[tok.charid] = true
    end
    local result = {}
    for _, charid in ipairs(dmhub.GetCharacterIdsInParty(GetDefaultPartyID()) or {}) do
        if not onMap[charid] then
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.properties ~= nil and IsHeroToken(tok) then
                result[#result + 1] = tok
            end
        end
    end
    table.sort(result, function(a, b) return (a.name or "") < (b.name or "") end)
    return result
end

--The hero count the monsters are balanced for, and whether it is the
--automatic one. Automatic = the heroes on the map; with none there yet, the
--party size the builder balances against.
--- @param record EncounterPrepRecord
--- @return number count
--- @return boolean auto
--- @return number onMap
local function BalanceCount(record)
    local heroes = PrepHeroes(record)
    local onMap = #heroes
    if type(record.heroOverride) == "number" then
        return math.max(1, math.min(MAX_HEROES, record.heroOverride)), false, onMap
    end
    if onMap > 0 then
        return math.min(MAX_HEROES, onMap), true, onMap
    end
    local party = Encounter.CurrentParty()
    return math.max(1, math.min(MAX_HEROES, party.numHeroes or 4)), true, onMap
end

--Free tiles for heroes arriving: the start zone's tiles first, then tiles
--around the middle of the region (or the camera).
--- @param encounter Encounter|nil
--- @param count number
--- @return Loc[]
local function ArrivalTiles(encounter, count)
    local result = {}
    local taken = {}
    local function Free(loc)
        local key = string.format("%d,%d,%d", loc.x, loc.y, loc.floorIndex or 0)
        if taken[key] then
            return false
        end
        if #(game.GetTokensAtLoc(loc) or {}) > 0 then
            return false
        end
        taken[key] = true
        return true
    end

    if encounter ~= nil then
        for _, loc in ipairs(Encounter.StartLocsOnCurrentMap(encounter:GetHeroStartLocs())) do
            if #result >= count then
                return result
            end
            if Free(loc) then
                result[#result + 1] = loc
            end
        end
    end

    local camera = dmhub.cameraPosition
    local ax, ay = round(camera.x), round(camera.y)
    local region = encounter ~= nil and encounter:GetRegion() or nil
    if region ~= nil then
        ax, ay = round((region.x1 + region.x2) / 2), round((region.y1 + region.y2) / 2)
    end
    local floorIndex = game.currentFloorIndex
    for r = 0, 15 do
        for dy = -r, r do
            for dx = -r, r do
                if #result >= count then
                    return result
                end
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local loc = core.Loc { x = ax + dx, y = ay + dy, floorIndex = floorIndex }
                    if Free(loc) then
                        result[#result + 1] = loc
                    end
                end
            end
        end
    end
    return result
end

--The stamina a monster of the group has at this hero count: the group's
--balancing figure when it has one, else the creature's own.
local function BalancedStamina(group, monsterid, numHeroes)
    local info = (group.balancing or {})[numHeroes]
    if info ~= nil and type(info.stamina) == "number" then
        return info.stamina
    end
    local asset = assets.monsters[monsterid]
    if asset ~= nil then
        return asset.properties.max_hitpoints
    end
    return nil
end

--Monsters that join the encounter when they turn up on the map during prep.
local function IsAdoptable(tok)
    if tok.properties == nil or not IsMonsterToken(tok) or IsPlayerSide(tok) then
        return false
    end
    if TryGet(tok.properties, "encounterPlacementId") ~= nil then
        return false
    end
    if tok.summonerid ~= nil and tok.summonerid ~= "" then
        return false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- The balancer: runs on the Director who started the prep
-- ---------------------------------------------------------------------------

--- @param mapid string
--- @param record EncounterPrepRecord
local function BalanceTick(mapid, record)
    local state = LocalState(mapid, record)
    if dmhub.Time() < state.settleUntil then
        return
    end
    local encounter = PlayEncounter(mapid, record)
    local numHeroes = BalanceCount(record)

    --forget deletes that have landed.
    for charid, _ in pairs(state.ourDeletes) do
        if dmhub.GetTokenById(charid) == nil then
            state.ourDeletes[charid] = nil
        end
    end

    local _, byKey, byGroup = PrepMonsters(record, encounter, state.ourDeletes)

    --monsters of the plan that left the map without the balancer deleting
    --them were deleted by hand; one that comes back (an undo) is un-counted.
    local present = {}
    for key, list in pairs(byKey) do
        for _, tok in ipairs(list) do
            present[tok.charid] = key
        end
    end
    local removedDelta = {}
    local anyDelta = false
    for charid, key in pairs(state.tracked) do
        if present[charid] == nil and state.removedIds[charid] == nil then
            state.removedIds[charid] = key
            removedDelta[key] = (removedDelta[key] or 0) + 1
            anyDelta = true
        end
    end
    for charid, key in pairs(present) do
        if state.removedIds[charid] ~= nil then
            state.removedIds[charid] = nil
            removedDelta[key] = (removedDelta[key] or 0) - 1
            anyDelta = true
        end
    end
    state.tracked = present

    --new monsters on the map join the encounter.
    local adopted = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if not state.known[tok.charid] then
            state.known[tok.charid] = true
            if IsAdoptable(tok) and not (record.added or {})[tok.charid] then
                adopted[#adopted + 1] = tok.charid
            end
        end
    end

    if anyDelta or #adopted > 0 then
        Encounter.ModifyPrep(mapid, "Encounter prep roster", function(rec)
            rec.removed = rec.removed or {}
            for key, delta in pairs(removedDelta) do
                local pid, monsterid = string.match(key, "^(.-)|(.*)$")
                if pid ~= nil then
                    rec.removed[pid] = rec.removed[pid] or {}
                    local n = math.max(0, (rec.removed[pid][monsterid] or 0) + delta)
                    rec.removed[pid][monsterid] = cond(n > 0, n, nil)
                end
            end
            rec.added = rec.added or {}
            for _, charid in ipairs(adopted) do
                rec.added[charid] = true
            end
        end)
        record = Encounter.GetPrep(mapid) or record
    end

    if encounter == nil then
        --a plan this client cannot see (not saved, started elsewhere): its
        --monsters stay as they are.
        return
    end

    --bring every group's count to what the hero count calls for.
    local changed = false
    local region = encounter:GetRegion()
    local camera = dmhub.cameraPosition
    local fallbackAnchor = { x = camera.x, y = camera.y }
    if region ~= nil then
        fallbackAnchor = { x = (region.x1 + region.x2) / 2, y = (region.y1 + region.y2) / 2 }
    end
    local deletes = {}
    for _, group in ipairs(encounter.groups) do
        local pid = group.placementid
        if group.wave == nil and pid ~= nil then
            local groupTokens = byGroup[pid] or {}
            local monsterids = {}
            for monsterid, _ in pairs(group.monsters or {}) do
                monsterids[#monsterids + 1] = monsterid
            end
            table.sort(monsterids)
            for _, monsterid in ipairs(monsterids) do
                local target = 0
                if group.minHeroes == nil or group.minHeroes <= numHeroes then
                    target = Encounter.AdjustedMonsterQuantity(group, monsterid, group.monsters[monsterid], numHeroes)
                end
                local removed = ((record.removed or {})[pid] or {})[monsterid] or 0
                target = math.max(0, target - removed)

                local current = byKey[Key(pid, monsterid)] or {}
                if #current < target then
                    local charids = Encounter.SpawnPrepMonsters(group, monsterid, target - #current, numHeroes, groupTokens,
                        Encounter.GroupHasUsableStaging(encounter, group), fallbackAnchor)
                    for _, charid in ipairs(charids) do
                        state.known[charid] = true
                    end
                    changed = true
                elseif #current > target then
                    --the last-placed go first.
                    for i = #current, target + 1, -1 do
                        local charid = current[i].charid
                        deletes[#deletes + 1] = charid
                        state.ourDeletes[charid] = true
                        state.tracked[charid] = nil
                    end
                    changed = true
                end
            end
        end
    end
    if #deletes > 0 then
        game.DeleteCharacters(deletes)
    end

    --stamina follows the group's balancing for the hero count.
    if state.lastBalance ~= numHeroes then
        state.lastBalance = numHeroes
        for _, group in ipairs(encounter.groups) do
            local pid = group.placementid
            if group.wave == nil and pid ~= nil and group.balancing ~= nil then
                for _, tok in ipairs(byGroup[pid] or {}) do
                    local monsterid = TryGet(tok.properties, "encounterSpawnMonster")
                    local stamina = monsterid ~= nil and BalancedStamina(group, monsterid, numHeroes) or nil
                    if stamina ~= nil and not state.ourDeletes[tok.charid] and tok.properties.max_hitpoints ~= stamina then
                        tok:ModifyProperties {
                            description = "Balance encounter",
                            undoable = false,
                            execute = function()
                                tok.properties.max_hitpoints = stamina
                            end,
                        }
                    end
                end
            end
        end
    end

    if changed then
        state.settleUntil = dmhub.Time() + SETTLE_SECONDS
    end
end

--Balancer errors already reported, so a failing pass does not flood the log.
local m_errorsReported = {}

dmhub.Coroutine(function()
    while true do
        coroutine.yield(TICK_SECONDS)
        if mod.unloaded then
            return
        end
        pcall(function()
            local mapid = game.currentMapId
            local record = Encounter.GetPrep(mapid)
            if record == nil or mapid == nil then
                return
            end
            local queue = dmhub.initiativeQueue
            if queue ~= nil and not queue.hidden then
                --combat started without going through the prep's Draw Steel.
                if dmhub.isDM then
                    Encounter.SetPrep(mapid, nil)
                end
                return
            end
            if record.by == dmhub.userid and dmhub.isDM then
                local ok, err = pcall(BalanceTick, mapid, record)
                if not ok then
                    --once per distinct error: the balancer retries every tick.
                    local text = "Encounter prep: " .. tostring(err)
                    if not m_errorsReported[text] then
                        m_errorsReported[text] = true
                        print(text)
                        dmhub.CloudError(text)
                    end
                end
            end
        end)
    end
end)

-- ---------------------------------------------------------------------------
-- Starting, ending and acting on a prep
-- ---------------------------------------------------------------------------

--Puts an encounter that has just been placed on the current map into prep.
--Called by PlaceEncounterForReal (EncounterPanel.lua) once its monsters are
--down. encounter is the play copy (its groups carry this play's placement ids).
--opts.savedEncounter: the plan it was copied from (for its id).
--- @param encounter Encounter
--- @param opts nil|{numHeroes: nil|number, savedEncounter: nil|Encounter}
function Encounter.BeginPrep(encounter, opts)
    opts = opts or {}
    local mapid = game.currentMapId
    if mapid == nil then
        return
    end

    local placementids = {}
    for groupIndex, group in ipairs(encounter.groups) do
        if group.placementid ~= nil then
            placementids["g" .. groupIndex] = group.placementid
        end
    end

    local saved = opts.savedEncounter or encounter
    local record = {
        encounterid = saved:try_get("id") or "",
        name = encounter:try_get("name", "Encounter"),
        by = dmhub.userid,
        prepid = dmhub.GenerateGuid(),
        startedAt = dmhub.serverTime,
        placementids = placementids,
        removed = {},
        added = {},
        excluded = {},
        heroOverride = nil,
    }
    m_playCopies[mapid] = { prepid = record.prepid, encounter = encounter }

    local state = LocalState(mapid, record)
    state.encounter = encounter
    --everything already on the map is not "new": only monsters placed from
    --now on join by turning up.
    for _, tok in ipairs(dmhub.allTokens) do
        state.known[tok.charid] = true
    end
    --what the plan placed counts as tracked from the start, so a monster
    --deleted before the first pass still counts as deleted by hand.
    local _, byKey = PrepMonsters(record, encounter, nil)
    for key, list in pairs(byKey) do
        for _, tok in ipairs(list) do
            state.tracked[tok.charid] = key
        end
    end
    state.lastBalance = opts.numHeroes

    Encounter.SetPrep(mapid, record)
    Encounter.ApplyRegion(encounter)
    Encounter.ShowStartZone(encounter)
    state.scripts = EncounterScript.PrepareEncounter(encounter, true)
end

--Ends the prep on the current map without starting combat. removeMonsters
--deletes the prep's monsters too.
--- @param removeMonsters boolean
function Encounter.CancelPrep(removeMonsters)
    local mapid = game.currentMapId
    local record = Encounter.GetPrep(mapid)
    if record == nil then
        return
    end
    if removeMonsters then
        local monsters = PrepMonsters(record, PlayEncounter(mapid, record), nil)
        local charids = {}
        for _, tok in ipairs(monsters) do
            charids[#charids + 1] = tok.charid
        end
        if #charids > 0 then
            game.DeleteCharacters(charids)
        end
    end
    Encounter.SetPrep(mapid, nil)
    Encounter.ClearStartZone(mapid)
    Encounter.RestoreRegionBounds(mapid)
    Encounter.ClearReadiedEncounter()
    m_local[mapid] = nil
    m_playCopies[mapid] = nil
end

--Summons heroes (charids) onto the current map, into the start zone.
--- @param charids string[]
function Encounter.SummonPrepHeroes(charids)
    local mapid = game.currentMapId
    local record = Encounter.GetPrep(mapid)
    local encounter = record ~= nil and PlayEncounter(mapid, record) or nil
    local tiles = ArrivalTiles(encounter, #charids)
    for i, charid in ipairs(charids) do
        local tok = dmhub.GetCharacterById(charid)
        local loc = tiles[i]
        if tok ~= nil and loc ~= nil then
            tok:ChangeLocation(loc.withGroundAltitude)
        end
    end
end

--The victory units the heroes face when combat starts from a prep: the
--monsters on the map (one per minion squad) plus the plan's reinforcements,
--which arrive later. Read by CreateCombatQueue (DSInitiativeRoll.lua).
--nonMinionsOnly counts only the non-minions, for "All Non-Minions Defeated".
--- @param encounter Encounter
--- @param monsterCharids table<string, boolean>
--- @param nonMinionsOnly boolean|nil
--- @return number
function Encounter.PrepOnsetMonsterCount(encounter, monsterCharids, nonMinionsOnly)
    local units = {}
    local count = 0
    for charid, _ in pairs(monsterCharids) do
        local tok = dmhub.GetCharacterById(charid)
        if tok ~= nil and tok.valid then
            local unit = Encounter.VictoryUnitKey(tok)
            if nonMinionsOnly and tok.properties.minion then
                unit = nil
            end
            if unit ~= nil and not units[unit] then
                units[unit] = true
                count = count + 1
            end
        end
    end

    local waves = DeepCopy(encounter)
    local waveGroups = {}
    for _, group in ipairs(waves.groups) do
        if group.wave ~= nil then
            waveGroups[#waveGroups + 1] = group
        end
    end
    waves.groups = waveGroups
    local record = Encounter.GetPrep(game.currentMapId)
    local numHeroes = record ~= nil and BalanceCount(record) or nil
    if nonMinionsOnly then
        return count + waves:CountNonMinionMonsters(numHeroes)
    end
    return count + waves:CountVictoryUnits(numHeroes)
end

--The tokens that fight when the prep's Draw Steel is pressed.
--- @param record EncounterPrepRecord
--- @param encounter Encounter|nil
--- @return CharacterToken[] heroSide
--- @return CharacterToken[] monsters
local function CombatSides(record, encounter)
    local heroes, allies = PrepHeroes(record)
    local heroSide = {}
    for _, tok in ipairs(heroes) do
        heroSide[#heroSide + 1] = tok
    end
    for _, tok in ipairs(allies) do
        heroSide[#heroSide + 1] = tok
    end
    local monsters = PrepMonsters(record, encounter, m_local[game.currentMapId] ~= nil and m_local[game.currentMapId].ourDeletes or nil)
    return heroSide, monsters
end

local function DrawSteel()
    local mapid = game.currentMapId
    local record = Encounter.GetPrep(mapid)
    if record == nil then
        return
    end
    local encounter = PlayEncounter(mapid, record)
    local heroSide, monsters = CombatSides(record, encounter)
    if #heroSide == 0 or #monsters == 0 then
        gui.ModalMessage {
            title = "Not Ready Yet",
            message = cond(#heroSide == 0, "There are no heroes on the map. Add them from the bar first.", "There are no monsters in the encounter."),
        }
        return
    end
    local ok, reason = Encounter.StartCombatWithTokens {
        playerTokens = heroSide,
        monsterTokens = monsters,
        encounter = encounter,
    }
    if not ok then
        gui.ModalMessage {
            title = "Cannot Draw Steel",
            message = string.format("Combat could not start: %s.", tostring(reason)),
        }
    end
end

local function ConfigureInitiative()
    local mapid = game.currentMapId
    local record = Encounter.GetPrep(mapid)
    if record == nil then
        return
    end
    local encounter = PlayEncounter(mapid, record)
    local _, monsters = CombatSides(record, encounter)
    local charids = {}
    for _, tok in ipairs(monsters) do
        charids[#charids + 1] = tok.charid
    end
    Encounter.ShowCombatSetupDialog(nil, encounter or Encounter.new { name = record.name }, charids)
end

-- ---------------------------------------------------------------------------
-- The prep bar (Director only), at the top of the map
-- ---------------------------------------------------------------------------

local PORTRAIT = 44

--A token's portrait as a button. opts: dim, badge, tooltip, click,
--rightClick, onRemove (shows a small x on hover).
local function Portrait(tok, opts)
    local children = {
        gui.CreateTokenImage(tok, {
            width = PORTRAIT,
            height = PORTRAIT,
            halign = "center",
            valign = "center",
        }),
    }
    if opts.badge ~= nil then
        children[#children + 1] = gui.Label {
            classes = { "sizeXs", "bold", "encounterPrepBadge" },
            floating = true,
            halign = "right",
            valign = "bottom",
            width = "auto",
            height = "auto",
            hpad = 3,
            borderBox = true,
            text = opts.badge,
        }
    end
    if opts.plus then
        children[#children + 1] = gui.Label {
            classes = { "sizeM", "bold", "encounterPrepPlus" },
            floating = true,
            halign = "center",
            valign = "center",
            width = "auto",
            height = "auto",
            interactable = false,
            text = "+",
        }
    end
    if opts.onRemove ~= nil then
        children[#children + 1] = gui.Button {
            classes = { "deleteButton", "sizeXs", "encounterPrepRemove" },
            floating = true,
            halign = "right",
            valign = "top",
            swallowPress = true,
            press = function()
                opts.onRemove()
            end,
        }
    end

    return gui.Panel {
        classes = { "encounterPrepPortrait", cond(opts.dim, "dim", nil) },
        width = PORTRAIT + 4,
        height = PORTRAIT + 4,
        hmargin = 2,
        bgimage = true,
        bgcolor = "clear",
        hover = function(element)
            if opts.tooltip ~= nil then
                gui.Tooltip(opts.tooltip)(element)
            end
        end,
        click = opts.click,
        rightClick = opts.rightClick,
        children = children,
    }
end

local function SelectToken(tok)
    dmhub.selectedTokens = { tok }
    pcall(function() dmhub.CenterOnToken(tok.charid) end)
end

local function PortraitRow(children)
    return gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        wrap = true,
        maxWidth = 520,
        children = children,
    }
end

--The bar's contents for the current prep. Rebuilt only when what it shows
--changes (see the signature in the bar's think).
--- @param record EncounterPrepRecord
--- @return Panel[]
local function BuildBarContents(record)
    local mapid = game.currentMapId
    local encounter = PlayEncounter(mapid, record)
    local state = LocalState(mapid, record)
    local heroes, allies, excluded = PrepHeroes(record)
    local missing = MissingHeroes()
    local _, monsters = CombatSides(record, encounter)
    local balanceFor, auto, onMap = BalanceCount(record)

    -- Heroes ---------------------------------------------------------------
    local heroPortraits = {}
    for _, tok in ipairs(heroes) do
        heroPortraits[#heroPortraits + 1] = Portrait(tok, {
            tooltip = string.format("%s\nClick to select. Right-click to leave out of the fight.", tok.name or "Hero"),
            click = function() SelectToken(tok) end,
            rightClick = function()
                Encounter.ModifyPrep(mapid, "Leave a hero out of the fight", function(rec)
                    rec.excluded = rec.excluded or {}
                    rec.excluded[tok.charid] = true
                end)
            end,
        })
    end
    for _, tok in ipairs(allies) do
        heroPortraits[#heroPortraits + 1] = Portrait(tok, {
            badge = "ally",
            tooltip = string.format("%s (ally)\nClick to select. Right-click to leave out of the fight.", tok.name or "Ally"),
            click = function() SelectToken(tok) end,
            rightClick = function()
                Encounter.ModifyPrep(mapid, "Leave an ally out of the fight", function(rec)
                    rec.excluded = rec.excluded or {}
                    rec.excluded[tok.charid] = true
                end)
            end,
        })
    end
    for _, tok in ipairs(excluded) do
        heroPortraits[#heroPortraits + 1] = Portrait(tok, {
            dim = true,
            badge = "out",
            tooltip = string.format("%s is left out of the fight. Click to bring them back in.", tok.name or "This creature"),
            click = function()
                Encounter.ModifyPrep(mapid, "Bring a hero into the fight", function(rec)
                    rec.excluded = rec.excluded or {}
                    rec.excluded[tok.charid] = nil
                end)
            end,
        })
    end

    local missingPortraits = {}
    local missingIds = {}
    for _, tok in ipairs(missing) do
        missingIds[#missingIds + 1] = tok.charid
        missingPortraits[#missingPortraits + 1] = Portrait(tok, {
            dim = true,
            plus = true,
            tooltip = string.format("%s is not on this map. Click to bring them into the start zone.", tok.name or "This hero"),
            click = function()
                Encounter.SummonPrepHeroes({ tok.charid })
            end,
        })
    end

    local heroCount = #heroes
    local heroColumn = gui.Panel {
        flow = "vertical",
        width = "50%",
        height = "auto",
        valign = "top",
        gui.Label {
            classes = { "sizeS", "bold" },
            width = "auto",
            height = "auto",
            halign = "center",
            text = string.format("Heroes: %d in the fight", heroCount),
        },
        PortraitRow(heroPortraits),
        gui.Panel {
            classes = { cond(#missing == 0, "collapsed", nil) },
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",
            tmargin = 4,
            gui.Label {
                classes = { "sizeXs", "fgMuted" },
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 4,
                text = "Not here:",
            },
            PortraitRow(missingPortraits),
            gui.Button {
                classes = { "sizeXs" },
                width = "auto",
                valign = "center",
                lmargin = 6,
                hpad = 8,
                borderBox = true,
                text = "Add All Heroes",
                hover = gui.Tooltip("Bring every hero in the party onto this map, into the start zone."),
                click = function()
                    Encounter.SummonPrepHeroes(missingIds)
                end,
            },
        },
    }

    -- Monsters -------------------------------------------------------------
    --one portrait per monster type per initiative group, with a count.
    local groups = {}
    local groupOrder = {}
    local ev = 0
    for _, tok in ipairs(monsters) do
        local props = tok.properties
        local evOk = pcall(function()
            if props.minion then
                ev = ev + props:EV() / GameSystem.minionsPerSquad
            else
                ev = ev + props:EV()
            end
        end)
        local _ = evOk
        local groupKey = TryGet(props, "initiativeGrouping") or tok.charid
        local typeKey = TryGet(props, "monster_type") or tok.name or tok.charid
        local key = groupKey .. "|" .. tostring(typeKey)
        local entry = groups[key]
        if entry == nil then
            entry = { tokens = {}, name = tostring(typeKey) }
            groups[key] = entry
            groupOrder[#groupOrder + 1] = key
        end
        table.insert(entry.tokens, tok)
    end
    ev = round(ev)

    local monsterPortraits = {}
    for _, key in ipairs(groupOrder) do
        local entry = groups[key]
        local first = entry.tokens[1]
        local n = #entry.tokens
        monsterPortraits[#monsterPortraits + 1] = Portrait(first, {
            badge = cond(n > 1, string.format("x%d", n), nil),
            tooltip = string.format("%s%s\nClick to select. The x deletes one.", entry.name, cond(n > 1, string.format(" (%d)", n), "")),
            click = function()
                dmhub.selectedTokens = entry.tokens
                pcall(function() dmhub.CenterOnToken(first.charid) end)
            end,
            onRemove = function()
                local last = entry.tokens[#entry.tokens]
                if last ~= nil and last.valid then
                    game.DeleteCharacters({ last.charid })
                end
            end,
        })
    end

    local strength = Encounter.PartyStrengthFromTokens(heroes)
    local tier = Encounter.DifficultyTier(ev, strength)
    local monsterColumn = gui.Panel {
        flow = "vertical",
        width = "50%",
        height = "auto",
        valign = "top",
        gui.Label {
            classes = { "sizeS", "bold" },
            width = "auto",
            height = "auto",
            halign = "center",
            text = string.format("Monsters: %d  -  EV %d  -  %s", #monsters, ev, cond(strength == nil, "no heroes yet", tier)),
        },
        PortraitRow(monsterPortraits),
        gui.Label {
            classes = { "sizeXs", "fgMuted" },
            width = "auto",
            height = "auto",
            halign = "center",
            tmargin = 2,
            text = "Delete monsters on the map, or drop more from the Bestiary: they join this fight.",
        },
    }

    -- Balancing ------------------------------------------------------------
    local balanceText
    if not auto then
        balanceText = string.format("Balanced for %d heroes (set by hand; %d on the map)", balanceFor, onMap)
    elseif onMap == 0 then
        balanceText = string.format("Balanced for %d heroes (the party size; none on the map yet)", balanceFor)
    else
        balanceText = string.format("Balanced for %d heroes (the heroes on the map)", balanceFor)
    end
    local function SetOverride(value)
        Encounter.ModifyPrep(mapid, "Encounter prep balancing", function(rec)
            rec.heroOverride = value
        end)
    end
    local balanceRow = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        valign = "center",
        gui.Button {
            classes = { "sizeXs", cond(balanceFor <= 1, "disabled", nil) },
            width = 26,
            text = "-",
            hover = gui.Tooltip("Balance the monsters for one fewer hero."),
            click = function()
                SetOverride(math.max(1, balanceFor - 1))
            end,
        },
        gui.Label {
            classes = { "sizeXs" },
            width = "auto",
            height = "auto",
            valign = "center",
            hmargin = 6,
            text = balanceText,
        },
        gui.Button {
            classes = { "sizeXs", cond(balanceFor >= MAX_HEROES, "disabled", nil) },
            width = 26,
            text = "+",
            hover = gui.Tooltip("Balance the monsters for one more hero."),
            click = function()
                SetOverride(math.min(MAX_HEROES, balanceFor + 1))
            end,
        },
        gui.Button {
            classes = { "sizeXs", cond(auto, "collapsed", nil) },
            width = "auto",
            lmargin = 6,
            hpad = 8,
            borderBox = true,
            text = "Auto",
            hover = gui.Tooltip("Balance for the heroes on the map again."),
            click = function()
                SetOverride(nil)
            end,
        },
    }

    -- Scripts --------------------------------------------------------------
    if state.scripts == nil and encounter ~= nil then
        state.scripts = EncounterScript.PrepareEncounter(encounter, false)
    end
    local scriptLabels = {}
    for _, script in ipairs(state.scripts or {}) do
        local text = script.name
        if script.error ~= nil then
            text = string.format("%s: %s", text, script.error)
        elseif script.victoryText ~= nil then
            text = string.format("%s: %s", text, script.victoryText)
        end
        scriptLabels[#scriptLabels + 1] = gui.Label {
            classes = { "sizeXs", cond(script.error ~= nil, "danger", "fgMuted") },
            width = "auto",
            height = "auto",
            maxWidth = 360,
            text = "Script - " .. text,
        }
    end
    local scriptColumn = gui.Panel {
        classes = { cond(#scriptLabels == 0, "collapsed", nil) },
        flow = "vertical",
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 16,
        children = scriptLabels,
    }

    return {
        gui.Panel {
            flow = "horizontal",
            width = "100%",
            height = "auto",
            gui.Label {
                classes = { "sizeXs", "fgMuted" },
                width = "auto",
                height = "auto",
                valign = "center",
                text = "PREPARING ENCOUNTER",
            },
            gui.Label {
                classes = { "sizeM", "bold" },
                width = "auto",
                height = "auto",
                valign = "center",
                lmargin = 10,
                text = record.name or "Encounter",
            },
            gui.Button {
                classes = { "sizeXs" },
                width = "auto",
                halign = "right",
                hpad = 8,
                borderBox = true,
                text = "Cancel",
                hover = gui.Tooltip("Stop preparing this encounter: its monsters and start zone are removed and the map goes back to normal."),
                click = function()
                    Encounter.CancelPrep(true)
                end,
            },
        },
        gui.Panel {
            flow = "horizontal",
            width = "100%",
            height = "auto",
            tmargin = 6,
            heroColumn,
            gui.Label {
                classes = { "sizeL", "bold" },
                width = 30,
                height = "auto",
                valign = "center",
                textAlignment = "center",
                text = "vs",
            },
            monsterColumn,
        },
        gui.Panel {
            flow = "horizontal",
            width = "100%",
            height = "auto",
            tmargin = 8,
            balanceRow,
            scriptColumn,
            gui.Panel {
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                gui.Button {
                    classes = { "sizeS" },
                    width = "auto",
                    hpad = 12,
                    borderBox = true,
                    rmargin = 8,
                    text = "Configure Initiative",
                    hover = gui.Tooltip("Open the Prepare Combat dialog: choose sides, groups, surprise and who goes first."),
                    click = function()
                        ConfigureInitiative()
                    end,
                },
                gui.Button {
                    classes = { "sizeL" },
                    width = "auto",
                    hpad = 18,
                    borderBox = true,
                    text = "Draw Steel!",
                    hover = gui.Tooltip("Start combat with the heroes and monsters shown here."),
                    click = function()
                        DrawSteel()
                    end,
                },
            },
        },
    }
end

--What the bar shows, as a string: the bar rebuilds when it changes.
--- @param record EncounterPrepRecord
--- @return string
local function BarSignature(record)
    local mapid = game.currentMapId
    local encounter = PlayEncounter(mapid, record)
    local heroes, allies, excluded = PrepHeroes(record)
    local parts = { tostring(record.prepid), tostring(record.heroOverride), tostring(encounter ~= nil) }
    for _, list in ipairs({ heroes, allies, excluded, MissingHeroes() }) do
        parts[#parts + 1] = "/"
        for _, tok in ipairs(list) do
            parts[#parts + 1] = tok.charid
        end
    end
    local _, monsters = CombatSides(record, encounter)
    local ids = {}
    for _, tok in ipairs(monsters) do
        ids[#ids + 1] = tok.charid
    end
    table.sort(ids)
    parts[#parts + 1] = "/"
    parts[#parts + 1] = table.concat(ids, ",")
    local state = m_local[mapid]
    parts[#parts + 1] = tostring(state ~= nil and state.scripts ~= nil)
    return table.concat(parts, " ")
end

local function BarStyles()
    return ThemeEngine.MergeStyles({
        {
            selectors = { "encounterPrepBar" },
            bgcolor = "@bg",
            borderColor = "@accent",
            borderWidth = 2,
            cornerRadius = 6,
        },
        {
            selectors = { "encounterPrepPortrait", "hover" },
            bgcolor = "@accent",
            cornerRadius = 4,
        },
        {
            selectors = { "encounterPrepPortrait", "dim" },
            opacity = 0.55,
        },
        {
            selectors = { "encounterPrepBadge" },
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 3,
        },
        {
            selectors = { "encounterPrepPlus" },
            color = "@fg",
        },
        {
            selectors = { "encounterPrepRemove" },
            hidden = 1,
        },
        {
            selectors = { "encounterPrepRemove", "parent:hover" },
            hidden = 0,
        },
    })
end

--The Director's prep bar, built into the map HUD (GameHud.lua wraps it in
--Tabletop.MapHudSlot, so it rides at the top of the live map window). Hidden
--unless the current map has a prep and no combat or Draw Steel banner.
--- @return Panel
function GameHud:CreateEncounterPrepBar()
    local bar
    bar = gui.Panel {
        classes = { "encounterPrepBar", "collapsed" },
        styles = BarStyles(),
        width = 1080,
        height = "auto",
        halign = "center",
        valign = "top",
        tmargin = 10,
        flow = "vertical",
        pad = 10,
        borderBox = true,
        bgimage = true,
        data = {
            signature = nil,
        },

        monitorGame = Encounter.PrepDocPath(),
        refreshGame = function(element)
            element:FireEvent("think")
        end,

        thinkTime = TICK_SECONDS,
        think = function(element)
            local record = nil
            local show = dmhub.isDM
            if show then
                record = Encounter.GetPrep(game.currentMapId)
                local queue = dmhub.initiativeQueue
                show = record ~= nil
                    and not (queue ~= nil and not queue.hidden)
                    and not Encounter.DrawSteelBannerActive()
            end
            element:SetClass("collapsed", not show)
            if not show or record == nil then
                element.data.signature = nil
                return
            end

            local signature = BarSignature(record)
            if signature == element.data.signature then
                return
            end
            element.data.signature = signature
            element.children = BuildBarContents(record)
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if bar ~= nil and bar.valid then
            bar.styles = BarStyles()
            bar.data.signature = nil
        end
    end)

    return bar
end
