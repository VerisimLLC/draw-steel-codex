--Encounter of the Week: reinforcements and the clear-the-map victory.
--
--Features of the "# Encounter" beat (the first and last parsed by
--EncounterScript.lua):
--
--  * "## Reinforcements: <Name>" sections. Each has an "Arrive:" schedule
--    (named rounds, or recurring), an "Enter:" zone type, optional "Shout:"
--    lines, and one or more [[encounter]] islands. At the START of every
--    round the schedule names, the host spawns the next island's monsters
--    (several islands take turns, one per arrival) in that zone, scaled to
--    the party like the opening encounter, and puts them in the initiative
--    so they act that round. One of them shouts a random "Shout:" line.
--  * The encounter builder's own reinforcement waves ("Add Reinforcements"
--    in the combat builder: Encounter.waves, each a name and a round, 2-6
--    or "every"; a wave's groups carry group.wave). Outside EotW the
--    Director deploys them from the initiative bar's Reinforcements strip;
--    an EotW game has no Director (and the authoring test runs as a player
--    host), so the host brings them in here: a numbered wave at the start
--    of its round (or on the first tick after it, if one was missed),
--    "every" at the start of every round from round 2. Spawned like a
--    section's island and marked deployed on the live encounter, so the
--    victory check stops counting them as still to come.
--  * "Victory: every Dwarf on the map is defeated" (or "every enemy ..."):
--    an extra way to win on top of the encounter's own condition. It counts
--    only the enemies standing on the map, never the ones still to come.
--
--Document state (eotwscript document, next to zoneSetup):
--  data.reinforcements = {
--    arrived = { ["<sectionId>-r<round>"] = { round, at, island, count },
--                ["wave-<waveid>-r<round>"] = { round, at, count, wave } },
--    spawned = { charid, ... },  -- every token that arrived, for test resets
--  }
--An arrival is stamped BEFORE its monsters spawn, so a failed spawn is never
--retried into a double wave. The stamp that decides whether a WAVE is due
--lives on the live encounter instead (deployedWaves, and eotwWaveRounds for
--"every"): that is made fresh for each combat, where the document's record
--is only cleared by a test reset.

local mod = dmhub.GetModLoading()

EncounterReinforcements = rawget(_G, "EncounterReinforcements") or {}

local function lower(s)
    return string.lower(tostring(s or ""))
end

--The map script's encounter beat (the first "# Encounter"), and the script.
function EncounterReinforcements.EncounterBeat(script)
    script = script or EncounterMontage.FindMapScript()
    for _, b in ipairs((script and script.parse and script.parse.beats) or {}) do
        if b.kind == "encounter" then
            return b, script
        end
    end
    return nil, script
end

--The authored Encounter behind one reinforcement island ({tag, line}).
--The annotation lives on the document the line came from (a sub-document
--keeps its own islands), under the journal's key for a repeated tag
--("encounter-1", "encounter-2", ...), exactly as a [[scene]] is found.
function EncounterReinforcements.IslandEncounter(script, island)
    if script == nil or island == nil then
        return nil
    end
    local docsTable = dmhub.GetTable("documents") or {}
    local doc = script.doc
    local key = island.tag
    local src = script.parse.sources ~= nil and script.parse.sources[island.line] or nil
    if src ~= nil then
        doc = docsTable[src.docid] or doc
        local text = ""
        pcall(function() text = doc:GetTextContent() or "" end)
        key = EncounterScript.AnnotationKey(text, island.tag, src.line)
    end
    if doc == nil then
        return nil
    end
    local annotations = doc:try_get("annotations")
    local tag = annotations ~= nil and annotations[key] or nil
    if tag == nil or tag.typeName ~= "RichEncounter" then
        return nil
    end
    return tag:try_get("encounter"), tag
end

--Every tile of the zone type on the current map, shuffled, the free ones
--first. Returns a list of core.Loc.
local function ZoneLocs(zone)
    local free, taken = {}, {}
    for _, z in ipairs(EncounterZones.ZoneRecords(zone)) do
        for _, l in ipairs(z.record.locs or {}) do
            --a series' part arrives only inside its own region.
            if EncounterZones.InPlayRegion(l.x, l.y) then
                local loc = core.Loc{ x = math.floor(l.x), y = math.floor(l.y), floorIndex = z.floorIndex }
                if game.GetTokensAtLoc(loc) == nil then
                    free[#free + 1] = loc
                else
                    taken[#taken + 1] = loc
                end
            end
        end
    end
    local function Shuffle(list)
        for i = #list, 2, -1 do
            local j = math.random(1, i)
            list[i], list[j] = list[j], list[i]
        end
    end
    Shuffle(free)
    Shuffle(taken)
    for _, loc in ipairs(taken) do
        free[#free + 1] = loc
    end
    return free
end

--`count` spawn locations from the zone, each tile used once while they
--last (the spawn's fitLocation nudges any overflow onto a free neighbour).
local function PickLocs(zoneLocs, count, used)
    local result = {}
    if #zoneLocs == 0 then
        return result
    end
    for _ = 1, count do
        used.n = used.n + 1
        result[#result + 1] = zoneLocs[((used.n - 1) % #zoneLocs) + 1]
    end
    return result
end

--Spawn one arrival. Host, elevated by the caller. Returns the spawned
--charids and the island index used.
local function Arrive(script, section, ordinal, queue, live)
    local islands = section.islands or {}
    if #islands == 0 then
        return {}, nil
    end
    local index = ((ordinal - 1) % #islands) + 1
    local encounter = EncounterReinforcements.IslandEncounter(script, islands[index])
    if encounter == nil then
        printf("EotW reinforcements: '%s' island %d has no encounter", tostring(section.name), index)
        return {}, index
    end

    --difficulty notches balance a wave like the opening fight (DifficultyBalance).
    local numHeroes, extraLevels = EncounterOfTheWeekGame.DifficultyBalance(tonumber(dmhub.GetSettingValue("numheroes")) or 5)
    local zoneLocs = section.zone ~= nil and ZoneLocs(section.zone) or {}
    if section.zone ~= nil and #zoneLocs == 0 then
        printf("EotW reinforcements: the map has no '%s' zone; '%s' arrive at their saved positions", tostring(section.zone), tostring(section.name))
    end
    local used = { n = 0 }

    local spawned = {}
    for _, group in ipairs(encounter.groups or {}) do
        local count = Encounter.AdjustedGroupCount(group, numHeroes)
        if count > 0 then
            --a copy, so the island's own record (and its "Save and Remove"
            --tags) is never touched; the zone replaces any saved positions.
            local copy = DeepCopy(group)
            copy.placementid = nil
            local anchor = (group.spawnlocs or {})[1] or dmhub.cameraPosition
            if #zoneLocs > 0 then
                copy.spawnlocs = PickLocs(zoneLocs, count, used)
                copy.spawnmonsters = nil
                copy.appearances = nil
                copy.invisibleToPlayers = nil
                copy.startsHidden = nil
                anchor = copy.spawnlocs[1]
            end
            local groupid, charids = Encounter.SpawnGroupForReal(copy, numHeroes, anchor)
            for _, charid in ipairs(charids) do
                spawned[#spawned + 1] = charid
                local token = dmhub.GetTokenById(charid)
                if token ~= nil then
                    token:ModifyProperties{
                        description = "Reinforcements",
                        undoable = false,
                        execute = function()
                            token.properties.eotwReinforcement = section.id
                        end,
                    }
                end
            end
            --they take their turns from this round on.
            if #charids > 0 and queue ~= nil then
                queue:SetInitiative(groupid, 0, 0)
            end
        end
    end
    --each wave is levelled on its own, like the opening fight.
    if #spawned > 0 then
        EncounterOfTheWeekGame.ApplyLevelBoost(spawned, EncounterOfTheWeekGame.LevelBoost(extraLevels), "reinforcements")
    end
    game.UpdateCharacterTokens()

    --their own card on the victory screen's Monsters tab.
    if #spawned > 0 and live ~= nil then
        pcall(function() live:RecordOnsetMonsterGroups(spawned) end)
    end
    return spawned, index
end

--One of the arrivals calls out a random "Shout:" line: a leader or other
--non-minion if there is one, so the squad's captain speaks for it.
local function Shout(section, charids)
    local shouts = section.shouts or {}
    if #shouts == 0 or #charids == 0 then
        return
    end
    local speaker = nil
    for _, charid in ipairs(charids) do
        local token = dmhub.GetTokenById(charid)
        if token ~= nil then
            local minion = false
            pcall(function() minion = token.properties.minion == true end)
            if not minion then
                speaker = token
                break
            end
            speaker = speaker or token
        end
    end
    if speaker == nil then
        return
    end
    local text = shouts[math.random(1, #shouts)]
    pcall(function()
        speaker:ModifyProperties{
            description = "Speech",
            undoable = false,
            execute = function()
                speaker.properties:CharacterSpeech{ text = text }
            end,
        }
    end)
end

--The arrivals due at the start of `round` that have not come yet.
local function DueArrivals(beat, round, arrived)
    local due = {}
    local story = nil
    for _, section in ipairs(beat.reinforcements or {}) do
        --"When <condition>:" above the heading: a series part's story
        --decides whether these come at all.
        local gateOpen = true
        if section.gate ~= nil then
            story = story or EncounterMontage.Story()
            gateOpen = EncounterScript.EvalStoryCondition(section.gate.cond, story)
        end
        if gateOpen and section.schedule ~= nil and #(section.islands or {}) > 0 then
            local ordinal = EncounterScript.ScheduleOrdinal(section.schedule, round)
            if ordinal > 0 then
                local key = string.format("%s-r%d", section.id, round)
                if arrived[key] == nil then
                    due[#due + 1] = { section = section, ordinal = ordinal, key = key }
                end
            end
        end
    end
    return due
end

--- encounter-builder waves --------------------------------------------------

--The last round an "every" wave arrived in, per wave id, on the live
--encounter (copy-on-write, like deployedWaves). Rides the initiative queue,
--so a new host after a handover sees it.
LiveEncounter.eotwWaveRounds = {}

--The waves of the live encounter due at the start of `round`.
local function DueWaves(live, round)
    local due = {}
    local everyRounds = live:try_get("eotwWaveRounds", {})
    for _, wave in ipairs(live:try_get("waves", {})) do
        if live:WaveHasMonsters(wave.id) then
            if wave.round == "every" then
                if round >= 2 and everyRounds[wave.id] ~= round then
                    due[#due + 1] = wave
                end
            elseif type(wave.round) == "number" and round >= wave.round and not live:IsWaveDeployed(wave.id) then
                due[#due + 1] = wave
            end
        end
    end
    return due
end

--Where a wave group with no saved positions comes in: the first saved
--position of its wave, else of any group in the encounter (the opening
--fight's ground), else the host's camera. SpawnGroupForReal lays the
--unplaced monsters out in a grid around it.
local function WaveAnchor(live, group)
    local own = (group.spawnlocs or {})[1]
    if own ~= nil then
        return own
    end
    local fallback = nil
    for _, other in ipairs(live.groups or {}) do
        local loc = (other.spawnlocs or {})[1]
        if loc ~= nil then
            if other.wave == group.wave then
                return loc
            end
            fallback = fallback or loc
        end
    end
    return fallback or dmhub.cameraPosition
end

--Spawn one wave's groups. Host, elevated by the caller. Returns the
--spawned charids.
local function ArriveWave(live, wave, queue)
    local numHeroes, extraLevels = EncounterOfTheWeekGame.DifficultyBalance(tonumber(dmhub.GetSettingValue("numheroes")) or 5)
    local spawned = {}
    local mountEntries = {}
    for groupIndex, group in ipairs(live.groups or {}) do
        if group.wave == wave.id and Encounter.AdjustedGroupCount(group, numHeroes) > 0 then
            --a copy, so the live encounter's group is never touched, and
            --without the placement id: these are not the builder's staging.
            local copy = DeepCopy(group)
            copy.placementid = nil
            local groupid, charids, mounts = Encounter.SpawnGroupForReal(copy, numHeroes, WaveAnchor(live, group))
            for _, charid in ipairs(charids) do
                spawned[#spawned + 1] = charid
                local token = dmhub.GetTokenById(charid)
                if token ~= nil then
                    token:ModifyProperties{
                        description = "Reinforcements",
                        undoable = false,
                        execute = function()
                            token.properties.eotwReinforcement = "wave-" .. wave.id
                        end,
                    }
                end
            end
            for _, m in ipairs(mounts or {}) do
                mountEntries[#mountEntries + 1] = { group = groupIndex, slot = m.slot, token = m.token }
            end
            --they take their turns from this round on.
            if #charids > 0 and queue ~= nil then
                queue:SetInitiative(groupid, 0, 0)
            end
        end
    end
    --riders saved in the saddle, as the Director's deploy does.
    if #mountEntries > 0 then
        pcall(function() Encounter.RestoreMounts(live, mountEntries) end)
    end
    --each wave is levelled on its own, like the opening fight.
    if #spawned > 0 then
        EncounterOfTheWeekGame.ApplyLevelBoost(spawned, EncounterOfTheWeekGame.LevelBoost(extraLevels), "reinforcements")
    end
    game.UpdateCharacterTokens()
    --their own card on the victory screen's Monsters tab.
    if #spawned > 0 then
        pcall(function() live:RecordOnsetMonsterGroups(spawned) end)
    end
    return spawned
end

--Host, from HostTick: bring in the live encounter's waves due this round.
local function WaveTick(queue, live, round)
    local due = DueWaves(live, round)
    if #due == 0 then
        return
    end

    --stamp first, on the live encounter (networked with the queue below):
    --a spawn that throws must not come round again next tick. An "every"
    --wave is marked deployed too, so it stops counting as still to come.
    for _, wave in ipairs(due) do
        live:MarkWaveDeployed(wave.id)
        if wave.round == "every" then
            live.eotwWaveRounds = DeepCopy(live:try_get("eotwWaveRounds", {}))
            live.eotwWaveRounds[wave.id] = round
        end
    end

    local results = {}
    ElevateToHostPermissions()
    for _, wave in ipairs(due) do
        local ok, spawned = pcall(ArriveWave, live, wave, queue)
        if not ok then
            printf("EotW reinforcements: wave '%s' failed to arrive: %s", tostring(wave.name), tostring(spawned))
            spawned = {}
        else
            printf("EotW reinforcements: round %d, wave '%s' (%s): %d monsters", round, tostring(wave.name), Encounter.WaveRoundText(wave), #spawned)
        end
        results[#results + 1] = { wave = wave, spawned = spawned }
    end
    pcall(function() dmhub:UploadInitiativeQueue() end)
    DropHostPermissions()

    --the document's record: for /eotwreinforce state and the test reset.
    local doc = EncounterMontage.GetDoc()
    doc:BeginChange()
    doc.data.reinforcements = doc.data.reinforcements or {}
    doc.data.reinforcements.arrived = doc.data.reinforcements.arrived or {}
    local list = doc.data.reinforcements.spawned or {}
    for _, r in ipairs(results) do
        doc.data.reinforcements.arrived[string.format("wave-%s-r%d", r.wave.id, round)] = {
            round = round, at = dmhub.serverTime, count = #r.spawned, wave = tostring(r.wave.name),
        }
        for _, charid in ipairs(r.spawned) do
            list[#list + 1] = charid
        end
    end
    doc.data.reinforcements.spawned = list
    doc:CompleteChange("Encounter of the Week: reinforcement waves arrived", { undoable = false })
end

--Host, every tick while combat is live and no outcome is pending: bring in
--whatever the current round's schedule says -- the script's sections and
--the encounter builder's waves. Idempotent per (section, round) through the
--document, per wave through the live encounter. `force` = {section index}
--brings that section's next arrival in now, whatever the round (the dev
--command).
function EncounterReinforcements.HostTick(queue, live, force)
    if queue == nil or queue.hidden then
        return
    end
    if force == nil and live ~= nil then
        local ok, err = pcall(WaveTick, queue, live, tonumber(queue.round) or 1)
        if not ok then
            printf("EotW reinforcements: wave tick failed: %s", tostring(err))
        end
    end
    local beat, script = EncounterReinforcements.EncounterBeat()
    if beat == nil or #(beat.reinforcements or {}) == 0 then
        return
    end
    local round = tonumber(queue.round) or 1
    local doc = EncounterMontage.GetDoc()
    local state = doc.data.reinforcements or {}
    local arrived = state.arrived or {}

    local due
    if force ~= nil then
        local section = beat.reinforcements[force.index or 1]
        if section == nil then
            print("EotW reinforcements: no such section")
            return
        end
        local n = 1
        for key, _ in pairs(arrived) do
            if string.sub(key, 1, #section.id + 2) == section.id .. "-r" then
                n = n + 1
            end
        end
        due = { { section = section, ordinal = n, key = string.format("%s-forced%d", section.id, n) } }
    else
        due = DueArrivals(beat, round, arrived)
    end
    if #due == 0 then
        return
    end

    --stamp first: a spawn that throws must not come round again next tick.
    doc:BeginChange()
    doc.data.reinforcements = doc.data.reinforcements or {}
    doc.data.reinforcements.arrived = doc.data.reinforcements.arrived or {}
    for _, d in ipairs(due) do
        doc.data.reinforcements.arrived[d.key] = { round = round, at = dmhub.serverTime }
    end
    doc:CompleteChange("Encounter of the Week: reinforcements", { undoable = false })

    local results = {}
    ElevateToHostPermissions()
    for _, d in ipairs(due) do
        local ok, spawned, index = pcall(Arrive, script, d.section, d.ordinal, queue, live)
        if not ok then
            printf("EotW reinforcements: '%s' failed to arrive: %s", tostring(d.section.name), tostring(spawned))
            spawned = {}
        else
            printf("EotW reinforcements: round %d, '%s' (arrival %d, island %s): %d monsters", round, d.section.name, d.ordinal, tostring(index), #spawned)
            Shout(d.section, spawned)
        end
        results[#results + 1] = { key = d.key, spawned = spawned, island = index }
    end
    pcall(function() dmhub:UploadInitiativeQueue() end)
    DropHostPermissions()

    doc = EncounterMontage.GetDoc()
    doc:BeginChange()
    doc.data.reinforcements = doc.data.reinforcements or {}
    local list = doc.data.reinforcements.spawned or {}
    for _, r in ipairs(results) do
        local record = doc.data.reinforcements.arrived[r.key]
        if record ~= nil then
            record.count = #r.spawned
            record.island = r.island
        end
        for _, charid in ipairs(r.spawned) do
            list[#list + 1] = charid
        end
    end
    doc.data.reinforcements.spawned = list
    doc:CompleteChange("Encounter of the Week: reinforcements arrived", { undoable = false })
end

--- monsters that fled an earlier part ------------------------------------
--The "Monsters Fled from Last Fight" Encounter Script (builtin:fled-monsters,
--`stragglers = true`) on a series part's opening encounter: the monsters the
--previous part's result lists as escaped through its Retreat Zone join this
--part's opening fight, in the encounter's Stragglers Zone, less one for each
--"one of the fleeing monsters is destroyed" clause (doc.data.retreatKills).
--A part recorded with a count but no list (a test's Story so far) is filled
--from that part's own opening fight.

--The bestiary entry for one fled monster: the entry it was spawned from,
--else the visible entry of its monster type.
local function FledMonsterId(rec)
    if rec.monsterid ~= nil and assets.monsters[rec.monsterid] ~= nil then
        return rec.monsterid
    end
    local wanted = lower(rec.monsterType or rec.name)
    local fallback = nil
    for id, m in pairs(assets.monsters) do
        local t, hidden = nil, false
        pcall(function()
            t = m.properties:try_get("monster_type")
            hidden = m.hidden == true
        end)
        if t ~= nil and lower(t) == wanted then
            if not hidden then
                return id
            end
            fallback = fallback or id
        end
    end
    return fallback
end

--The monsters of a series part's own opening fight, one bestiary id per
--creature, non-minions first (who flees first when only a count is known).
local function PartFightMonsters(part)
    local ids = {}
    pcall(function()
        local found = EncounterMontage.ScriptForMap(game.currentMapId)
        for _, script in ipairs(found.parts or {}) do
            if script.parse.part ~= nil and script.parse.part.number == part and script.doc ~= nil then
                local tag = (script.doc:try_get("annotations") or {})["encounter"]
                local enc = tag ~= nil and tag:try_get("encounter") or nil
                local minions = {}
                for _, group in ipairs(enc ~= nil and enc.groups or {}) do
                    if group.wave == nil then
                        for id, count in pairs(group.monsters or {}) do
                            local isMinion = false
                            pcall(function() isMinion = assets.monsters[id].properties.minion == true end)
                            for _ = 1, tonumber(count) or 0 do
                                if isMinion then
                                    minions[#minions + 1] = id
                                else
                                    ids[#ids + 1] = id
                                end
                            end
                        end
                    end
                end
                for _, id in ipairs(minions) do
                    ids[#ids + 1] = id
                end
            end
        end
    end)
    return ids
end

--Who the encounter's "Monsters Fled from Last Fight" script brings in:
--{ part, monsters = { bestiary id, ... }, kills }, or nil when the encounter
--has no such script or this is not a later part of a series.
function EncounterReinforcements.RetreatedJoining(encounter)
    if encounter == nil or not encounter:HasStragglersScript() then
        return nil
    end
    local part = (tonumber(EncounterOfTheWeekGame.ActivePart()) or 1) - 1
    if part < 1 then
        return nil
    end
    local list = {}
    local rec = EncounterMontage.Story().parts[part]
    if type(rec) == "table" then
        for _, r in ipairs(rec.retreated or {}) do
            local id = FledMonsterId(r)
            if id ~= nil then
                list[#list + 1] = id
            else
                printf("EotW: no bestiary entry for '%s', which fled Part %d", tostring(r.monsterType or r.name), part)
            end
        end
        local count = tonumber(rec.retreats) or #list
        if #list < count then
            local fight = PartFightMonsters(part)
            for i = #list + 1, math.min(count, #fight) do
                list[#list + 1] = fight[i]
            end
        end
    end
    local kills = tonumber(EncounterMontage.GetDoc().data.retreatKills) or 0
    for _ = 1, kills do
        if #list == 0 then
            break
        end
        table.remove(list, math.random(#list))
    end
    return { part = part, monsters = list, kills = kills }
end

--The encounter's Stragglers Zone tiles on the current map, shuffled, the
--free ones first.
local function StragglerLocs(encounter)
    local free, taken = {}, {}
    for _, loc in ipairs(Encounter.StartLocsOnCurrentMap(encounter:GetStragglerLocs())) do
        if game.GetTokensAtLoc(loc) == nil then
            free[#free + 1] = loc
        else
            taken[#taken + 1] = loc
        end
    end
    for _, list in ipairs({ free, taken }) do
        for i = #list, 2, -1 do
            local j = math.random(1, i)
            list[i], list[j] = list[j], list[i]
        end
    end
    for _, loc in ipairs(taken) do
        free[#free + 1] = loc
    end
    return free
end

--Host, from the opening spawn (EncounterOfTheWeekGame.SpawnEncounterGroups):
--spawn the monsters that fled the previous part, one initiative group per
--monster type, in the encounter's Stragglers Zone (else around `anchor`).
--Returns the spawned charids.
function EncounterReinforcements.SpawnRetreatedJoining(encounter, numHeroes, anchor)
    local joining = EncounterReinforcements.RetreatedJoining(encounter)
    if joining == nil then
        return {}
    end
    if #joining.monsters == 0 then
        printf("EotW: no monsters that fled Part %d join the fight (%d destroyed on the way)", joining.part, joining.kills)
        return {}
    end
    local counts, order = {}, {}
    for _, id in ipairs(joining.monsters) do
        if counts[id] == nil then
            counts[id] = 0
            order[#order + 1] = id
        end
        counts[id] = counts[id] + 1
    end
    local zoneLocs = StragglerLocs(encounter)
    if #zoneLocs == 0 then
        printf("EotW: the encounter has no Stragglers Zone; the monsters that fled Part %d arrive beside the fight", joining.part)
    end
    local used = { n = 0 }
    local spawned = {}
    for _, id in ipairs(order) do
        local group = { monsters = { [id] = counts[id] } }
        local at = anchor or dmhub.cameraPosition
        if #zoneLocs > 0 then
            group.spawnlocs = PickLocs(zoneLocs, counts[id], used)
            at = group.spawnlocs[1]
        end
        local _, charids = Encounter.SpawnGroupForReal(group, numHeroes, at)
        for _, charid in ipairs(charids) do
            spawned[#spawned + 1] = charid
        end
    end
    printf("EotW: %d monster(s) that fled Part %d join the fight in the Stragglers Zone (%d destroyed on the way)", #spawned, joining.part, joining.kills)
    return spawned
end

--- the clear-the-map victory ----------------------------------------------

--The beat's "Victory:" instruction, or nil.
function EncounterReinforcements.VictoryInstruction(beat)
    for _, ins in ipairs((beat and beat.setup) or {}) do
        if ins.kind == "victory" and ins.condition == "clearmap" then
            return ins
        end
    end
    return nil
end

--Is this token one of `who` ("dwarf": a monster keyword, or a word of its
--bestiary type; nil = any enemy)?
local function IsKind(token, who)
    if who == nil then
        return true
    end
    local match = false
    pcall(function()
        for keyword, _ in pairs(token.properties:try_get("keywords") or {}) do
            if lower(keyword) == who then
                match = true
            end
        end
        if not match then
            local mtype = " " .. lower(token.properties:try_get("monster_type") or "") .. " "
            match = string.find(mtype, " " .. who .. " ", 1, true) ~= nil
        end
    end)
    return match
end

--The enemies still standing on the map: monsters not fighting for the heroes,
--not the script's bystanders, not dead. `who` narrows it (see IsKind).
function EncounterReinforcements.LivingEnemies(who)
    local result = {}
    for _, token in ipairs(dmhub.allTokens) do
        if token.valid and token.properties ~= nil and not Encounter.FightsForHeroes(token) then
            local isMonster, isHero, dead = false, false, false
            pcall(function()
                isMonster = token.properties:IsMonster()
                isHero = token.properties:IsHero()
                dead = token.properties:IsDead()
            end)
            if isMonster and not isHero and not dead and IsKind(token, who) then
                local bystander = false
                pcall(function() bystander = EncounterOfTheWeekGame.IsBystander(token) end)
                if not bystander then
                    result[#result + 1] = token
                end
            end
        end
    end
    return result
end

--- the "Mark:" line: markers on the creatures the heroes must deal with ------

--The script's "Mark:" lines, each with the ids of the reinforcement sections
--it names. Cached until the game's content changes: the arrows ask many times a second.
local m_marks = nil
local m_marksUpdate = nil
local function MarkSpecs()
    if m_marks ~= nil and m_marksUpdate == dmhub.gameContentUpdateSeq then
        return m_marks
    end
    local specs = {}
    pcall(function()
        local beat = EncounterReinforcements.EncounterBeat()
        if beat == nil then
            return
        end
        for _, ins in ipairs(beat.setup or {}) do
            if ins.kind == "mark" then
                local sections = {}
                for _, section in ipairs(beat.reinforcements or {}) do
                    local name = lower(section.name)
                    name = string.gsub(name, "^the%s+", "")
                    for _, markName in ipairs(ins.names) do
                        if markName.text == name then
                            sections[section.id] = true
                        end
                    end
                end
                specs[#specs + 1] = { ins = ins, sections = sections }
            end
        end
    end)
    m_marks = specs
    m_marksUpdate = dmhub.gameContentUpdateSeq
    return specs
end

--Is this token one of the creatures a "Mark:" spec names?
local function MatchesMark(token, spec)
    local section = nil
    pcall(function() section = token.properties:try_get("eotwReinforcement") end)
    if section ~= nil and spec.sections[section] then
        return true
    end
    local tokenName = lower(token.name)
    for _, markName in ipairs(spec.ins.names) do
        local text = markName.text
        if tokenName == text or string.sub(tokenName, 1, #text + 1) == text .. " " then
            return true
        end
        if IsKind(token, text) or (markName.singular ~= text and IsKind(token, markName.singular)) then
            return true
        end
    end
    return false
end

--Marks show only during an EotW fight.
local function MarksActive()
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return false
    end
    local eotw = false
    pcall(function() eotw = EncounterOfTheWeekGame.IsEotwGame() end)
    return eotw and #MarkSpecs() > 0
end

--The living enemies the script's "Mark:" lines name.
function EncounterReinforcements.MarkedEnemies()
    local result = {}
    local specs = MarkSpecs()
    for _, token in ipairs(EncounterReinforcements.LivingEnemies(nil)) do
        for _, markSpec in ipairs(specs) do
            if MatchesMark(token, markSpec) then
                result[#result + 1] = token
                break
            end
        end
    end
    return result
end

--The charids that get an arrow, worked out at most twice a second and shared
--by every arrow (finding them walks every token on the map).
local m_markedSet = {}
local m_markedTime = nil
local function MarkedSet()
    local now = dmhub.Time()
    if m_markedTime ~= nil and now - m_markedTime < 0.5 then
        return m_markedSet
    end
    local set = {}
    if MarksActive() then
        for _, token in ipairs(EncounterReinforcements.MarkedEnemies()) do
            set[token.charid] = true
        end
    end
    m_markedSet = set
    m_markedTime = now
    return set
end

--The pointers, drawn in screen space on every client: a red arrow bobbing
--over each marked creature in view, and one at the edge of the view pointing
--toward each marked creature out of it. Nothing is written to the game.
local MARK_COLOR = "#e0402a"
local ARROW_W = 28
local ARROW_H = 22
local EDGE_MARGIN = 36
--Edge arrows stay below the initiative bar and objective line across the top.
local TOP_INSET = 270

local m_markOverlay = nil

--A world point in the overlay's units (origin top left, y down).
local function WorldToOverlay(wx, wy, bounds, width, height)
    return (wx - bounds.x1) / (bounds.x2 - bounds.x1) * width, (1 - (wy - bounds.y1) / (bounds.y2 - bounds.y1)) * height
end

--Puts one arrow per marked creature; spare arrows are hidden, not destroyed.
--- @param overlay Panel
local function UpdateMarkOverlay(overlay)
    local arrows = overlay.data.arrows
    local used = 0
    local bounds = dmhub.cameraBounds
    local usable = dmhub.cameraUsableBounds
    local width, height = overlay.renderedWidth, overlay.renderedHeight
    if bounds ~= nil and usable ~= nil and bounds.x2 > bounds.x1 and bounds.y2 > bounds.y1
        and type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
        --how far the arrows bob, in overlay units (up to 10): arrows over a token
        --move 60% of it, edge arrows 40%, so the edge ones don't bounce off the screen.
        local bob = math.abs(math.sin(dmhub.Time() * 4)) * 10
        --the part of the screen not under the docks, shrunk so edge arrows sit inside it.
        local ux1, uy1 = WorldToOverlay(usable.x1, usable.y2, bounds, width, height)
        local ux2, uy2 = WorldToOverlay(usable.x2, usable.y1, bounds, width, height)
        ux1, uy1, ux2, uy2 = ux1 + EDGE_MARGIN, math.max(uy1 + EDGE_MARGIN, TOP_INSET), ux2 - EDGE_MARGIN, uy2 - EDGE_MARGIN
        local cx, cy = (ux1 + ux2) / 2, (uy1 + uy2) / 2
        for charid, _ in pairs(MarkedSet()) do
            local token = dmhub.GetTokenById(charid)
            if token ~= nil and token.valid and token.hasTokenOnThisMap and not token.invisibleToPlayers then
                local pos = token.pos
                local tx, ty = WorldToOverlay(pos.x, pos.y, bounds, width, height)
                local x, y, angle
                if tx >= ux1 and tx <= ux2 and ty >= uy1 and ty <= uy2 then
                    --in view: above the token, pointing down at it.
                    local half = (token.tileSize or 1) * 0.5 * width / (bounds.x2 - bounds.x1)
                    x, y, angle = tx, ty - half - ARROW_H / 2 - 4 - bob * 0.6, 0
                else
                    --out of view: where the line from the view's centre to it
                    --leaves the view, pointing along that line.
                    local dx, dy = tx - cx, ty - cy
                    local scale = 1
                    if dx ~= 0 then
                        scale = math.min(scale, ((dx > 0 and ux2 or ux1) - cx) / dx)
                    end
                    if dy ~= 0 then
                        scale = math.min(scale, ((dy > 0 and uy2 or uy1) - cy) / dy)
                    end
                    local len = math.sqrt(dx * dx + dy * dy)
                    x, y = cx + dx * scale, cy + dy * scale
                    if len > 0 then
                        x, y = x + dx / len * bob * 0.4, y + dy / len * bob * 0.4
                    end
                    --the triangle image points down at rotate 0.
                    angle = math.deg(math.atan(dx, dy))
                end
                used = used + 1
                local arrow = arrows[used]
                if arrow == nil then
                    arrow = gui.Panel{
                        interactable = false,
                        bgimage = "panels/triangle.png",
                        bgcolor = MARK_COLOR,
                        width = ARROW_W,
                        height = ARROW_H,
                        halign = "left",
                        valign = "top",
                    }
                    arrows[used] = arrow
                    overlay:AddChild(arrow)
                end
                arrow:SetClass("collapsed", false)
                arrow.x = x - ARROW_W / 2
                arrow.y = y - ARROW_H / 2
                arrow.selfStyle.rotate = angle
            end
        end
    end
    for i = used + 1, #arrows do
        arrows[i]:SetClass("collapsed", true)
    end
end

--Puts the overlay up while a marked creature stands in an EotW fight, and
--takes it down after. A slow poll, so it heals itself across reloads.
dmhub.Coroutine(function()
    while true do
        coroutine.yield(0.5)
        local want = false
        if not mod.unloaded then
            pcall(function() want = next(MarkedSet()) ~= nil end)
        end
        local shown = m_markOverlay ~= nil and m_markOverlay.valid
        --a reload rebuilds the HUD, so the old parent can be a destroyed panel.
        local parent = GameHud.instance and GameHud.instance.parentPanel or nil
        if want and not shown and parent ~= nil and parent.valid then
            m_markOverlay = gui.Panel{
                interactable = false,
                blocksGameInteraction = false,
                width = "100%",
                height = "100%",
                halign = "center",
                valign = "center",
                styles = {
                    { selectors = { "collapsed" }, collapsed = 1 },
                },
                data = { arrows = {} },
                thinkTime = 0.03,
                think = function(element)
                    UpdateMarkOverlay(element)
                end,
            }
            parent:AddChild(m_markOverlay)
        elseif not want and shown then
            ---@cast m_markOverlay -nil
            m_markOverlay:DestroySelf()
            m_markOverlay = nil
        end
        if mod.unloaded then
            return
        end
    end
end)

--Host, while combat is live: true once the script's "Victory:" line is met.
function EncounterReinforcements.ClearMapVictory()
    local beat = EncounterReinforcements.EncounterBeat()
    local ins = EncounterReinforcements.VictoryInstruction(beat)
    if ins == nil then
        return false
    end
    return #EncounterReinforcements.LivingEnemies(ins.who) == 0
end

--- test reset ----------------------------------------------------------------

--The charids every arrival spawned (for /eotwmontage reset and End Test),
--including any tagged token the document lost track of.
function EncounterReinforcements.SpawnedTokens(doc)
    local result = {}
    for _, charid in ipairs(((doc.data.reinforcements or {}).spawned) or {}) do
        result[#result + 1] = charid
    end
    for _, tok in ipairs(dmhub.allTokens) do
        local tag = nil
        pcall(function() tag = tok.properties:try_get("eotwReinforcement") end)
        if tag ~= nil then
            result[#result + 1] = tok.charid
        end
    end
    return result
end

--- dev command -----------------------------------------------------------------

local function ReinforceCommand(str)
    local args = {}
    for word in string.gmatch(str or "", "%S+") do
        args[#args + 1] = word
    end
    local beat = EncounterReinforcements.EncounterBeat(EncounterMontage.FindMapScript(true))
    if args[1] == nil or args[1] == "state" then
        if beat == nil then
            print("EotW reinforcements: this map's script has no encounter beat")
            return
        end
        for i, r in ipairs(beat.reinforcements or {}) do
            printf("%d. %s: %s, enter %s, %d island(s), %d shout(s)", i, r.name,
                r.schedule ~= nil and EncounterScript.DescribeSchedule(r.schedule) or "NO SCHEDULE",
                tostring(r.zone or "(saved positions)"), #r.islands, #r.shouts)
        end
        --the encounter builder's waves, as the live combat holds them.
        local q = dmhub.initiativeQueue
        local live = q ~= nil and not q.hidden and q:try_get("liveEncounter") or nil
        if type(live) == "table" then
            for _, wave in ipairs(live:try_get("waves", {})) do
                printf("wave %s: %s, %s%s", tostring(wave.name), Encounter.WaveRoundText(wave),
                    cond(live:IsWaveDeployed(wave.id), "arrived", "to come"),
                    cond(live:WaveHasMonsters(wave.id), "", " (NO MONSTERS)"))
            end
        end
        local ins = EncounterReinforcements.VictoryInstruction(beat)
        if ins ~= nil then
            printf("Victory: %s (%d standing now)", EncounterScript.DescribeVictory(ins), #EncounterReinforcements.LivingEnemies(ins.who))
        end
        local state = EncounterMontage.GetDoc().data.reinforcements or {}
        for key, rec in pairs(state.arrived or {}) do
            printf("arrived %s: round %s, island %s, %s monsters", key, tostring(rec.round), tostring(rec.island), tostring(rec.count))
        end
        return
    end
    if args[1] == "arrive" then
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            print("EotW reinforcements: start combat first")
            return
        end
        local live = q:try_get("liveEncounter")
        if type(live) ~= "table" then
            live = nil
        end
        EncounterReinforcements.HostTick(q, live, { index = tonumber(args[2]) or 1 })
        return
    end
    print("usage: /eotwreinforce [state | arrive <section number>]")
end

pcall(function()
    Commands.RegisterMacro{
        name = "eotwreinforce",
        summary = "inspect or bring in Encounter of the Week reinforcements",
        doc = "Usage: /eotwreinforce [state | arrive <n>]\nstate lists the current map script's reinforcement sections, the live combat's encounter-builder waves, the Victory: line and what has arrived; arrive <n> brings section n's next arrival in now (combat must be live).",
        command = ReinforceCommand,
    }
end)
