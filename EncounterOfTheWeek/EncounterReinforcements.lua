--Encounter of the Week: reinforcements and the clear-the-map victory.
--
--Two features of the "# Encounter" beat, both parsed by EncounterScript.lua:
--
--  * "## Reinforcements: <Name>" sections. Each has an "Arrive:" schedule
--    (named rounds, or recurring), an "Enter:" zone type, optional "Shout:"
--    lines, and one or more [[encounter]] islands. At the START of every
--    round the schedule names, the host spawns the next island's monsters
--    (several islands take turns, one per arrival) in that zone, scaled to
--    the party like the opening encounter, and puts them in the initiative
--    so they act that round. One of them shouts a random "Shout:" line.
--  * "Victory: every Dwarf on the map is defeated" (or "every enemy ..."):
--    an extra way to win on top of the encounter's own condition. It counts
--    only the enemies standing on the map, never the ones still to come.
--
--Document state (eotwscript document, next to zoneSetup):
--  data.reinforcements = {
--    arrived = { ["<sectionId>-r<round>"] = { round, at, island, count } },
--    spawned = { charid, ... },  -- every token that arrived, for test resets
--  }
--An arrival is stamped BEFORE its monsters spawn, so a failed spawn is never
--retried into a double wave.

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
            local loc = core.Loc{ x = math.floor(l.x), y = math.floor(l.y), floorIndex = z.floorIndex }
            if game.GetTokensAtLoc(loc) == nil then
                free[#free + 1] = loc
            else
                taken[#taken + 1] = loc
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

    local numHeroes = tonumber(dmhub.GetSettingValue("numheroes")) or 5
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
    for _, section in ipairs(beat.reinforcements or {}) do
        if section.schedule ~= nil and #(section.islands or {}) > 0 then
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

--Host, every tick while combat is live and no outcome is pending: bring in
--whatever the current round's schedule says. Idempotent per (section,
--round) through the document. `force` = {section index} brings that
--section's next arrival in now, whatever the round (the dev command).
function EncounterReinforcements.HostTick(queue, live, force)
    if queue == nil or queue.hidden then
        return
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

--The enemies still standing on the map: monsters nobody controls, not the
--script's bystanders, not dead. `who` narrows it (see IsKind).
function EncounterReinforcements.LivingEnemies(who)
    local result = {}
    for _, token in ipairs(dmhub.allTokens) do
        if token.valid and token.properties ~= nil and not token.playerControlled then
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
        doc = "Usage: /eotwreinforce [state | arrive <n>]\nstate lists the current map script's reinforcement sections, the Victory: line and what has arrived; arrive <n> brings section n's next arrival in now (combat must be live).",
        command = ReinforceCommand,
    }
end)
