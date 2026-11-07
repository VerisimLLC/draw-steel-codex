local mod = dmhub.GetModLoading()

--Encounter of the Week: the Gauntlet runtime.
--
--A "# Gauntlet" beat is parsed as a montage beat with gauntlet = true
--(EncounterScript.lua, "gauntlets") and played by the montage runtime
--(EncounterMontage.lua), which calls in here at the few points where the
--rules differ. Design: GAUNTLET_PLAN.md at the dmhub repo root.
--
--How it plays: the party meets one section at a time.
--  * A CHALLENGE shows every option at once. Any player claims one for one
--    of their heroes ("claim"); the first claim wins. The claim becomes the
--    montage turn, which plays the option's own lines, then the ASSIST step
--    (one other hero may assist: "assist" / "assistRolled"), then the roll
--    once the claiming player presses Make the test ("proceedTest"), then
--    perks, dice and the outcome, exactly as a montage test does.
--  * A CHOICE ("Choose together:") is a party vote, one per player, settled
--    like a narrative vote (a split goes to a random voter).
--  * A custom event point ("## Custom Event") plays the first registered
--    event that is ready (EncounterGauntlet.RegisterCustomEvent), or is
--    passed over silently.
--  * Every roll a hero makes in the Gauntlet (assists and Pardon My Friend
--    included) adds a bane to their later rolls ("Weary").
--  After each section the party moves on by its route
--  (EncounterScript.GauntletNext); past the last section the beat is done.
--
--Authority is the montage's: the host is the only writer of
--data.montage, players stamp requests, and a player's own client rolls.
--
--State, on the montage document (data.montage):
--  gauntlet = {
--    section   = nil | entry id,        -- the section on the board (a
--                                          custom event's entry while one
--                                          plays)
--    eventPoint = nil | section id,     -- the event point that event came
--                                          from (its exit is the route on)
--    path      = { entry id, ... },     -- what the party has met, in order
--    skipped   = { section id, ... },   -- event points with nothing ready
--    rolls     = { [charid] = n },      -- rolls made: the fatigue count
--    events    = { [pointId] = { eventId, record } | false },
--    vote      = nil | { sectionId, choices = { [voterKey] = { optionIndex,
--                  userid, at } }, decision = nil | { candidates, winner,
--                  winnerName, optionIndex, optionName, startedAt },
--                  result = nil | { optionIndex, optionName, decidedBy,
--                  applied, at } },
--    ritualUsed = { [charid] = true },  -- Ritualist: once per Gauntlet
--  }
--  turn.gauntlet = true on every turn a Gauntlet makes. turn.arrival = true
--  on the turn that only plays a section's arrival scene (no hero). The
--  assist rides on the turn:
--  turn.assist = nil | { userid, heroid, heroName, rollSeq, startedAt,
--                        tier, total, outcome = "bane"|"edge"|"doubleedge"|nil }
--  turn.testAttrid = the characteristic the test (and so the assist) uses.

EncounterGauntlet = rawget(_G, "EncounterGauntlet") or {}

local T = UIText.T

--how long a section's result stays on screen before the party moves on.
local RESULT_LINGER_SECONDS = 4
--the same, for a result that applied nothing worth reading.
local RESULT_LINGER_QUIET = 1.5
--a claimed assist that is never rolled is handed back after this long.
local ASSIST_ROLL_SECONDS = 300

--assist tier -> what it does to the test it helps. Put Your Back Into It!
--turns the tier 1 bane into nothing.
local ASSIST_OUTCOMES = { "bane", "edge", "doubleedge" }
local ASSIST_MODTYPES = { bane = "bane", edge = "edge", doubleedge = "double_edge" }

--The montage's private helpers this file shares (EncounterMontage.Internal).
local function M()
    return EncounterMontage.Internal
end

local function Now()
    return dmhub.serverTime
end

--- custom events ----------------------------------------------------------------
--
--An event from outside the script that a "## Custom Event" point can play.
--  id        unique string (also part of the entry id; letters and digits)
--  priority  higher goes first when several are ready (default 0)
--  available function(heroes, doc) -> record | nil: ready to play? The
--            record is plain data saved on the document (strings, numbers).
--  text      function(record) -> the event as Gauntlet script text: a
--            "# Gauntlet" heading and ONE "## <Name>" section.
--  adjust    optional function(entry, record): change the parsed section
--            (effects the grammar cannot write).
--  played    optional function(doc, record): the host, inside an open
--            change of `doc`, as the event is chosen (mark it done).
local g_events = {}
local g_eventOrder = 0

function EncounterGauntlet.RegisterCustomEvent(args)
    g_eventOrder = g_eventOrder + 1
    local def = {
        id = args.id,
        priority = tonumber(args.priority) or 0,
        available = args.available,
        text = args.text,
        adjust = args.adjust,
        played = args.played,
        order = g_eventOrder,
    }
    g_events[def.id] = def
end

local function EventsByPriority()
    local list = {}
    for _, def in pairs(g_events) do
        list[#list + 1] = def
    end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.order < b.order
    end)
    return list
end

--The first ready event, already marked as played; nil when none is ready.
--Host, inside an open change of `doc`.
local function ChooseEvent(doc, heroes)
    for _, def in ipairs(EventsByPriority()) do
        local ok, record = pcall(def.available, heroes, doc)
        if not ok then
            printf("EotW gauntlet: custom event '%s' failed to check: %s", tostring(def.id), tostring(record))
        elseif record ~= nil then
            if def.played ~= nil then
                local playedOk, err = pcall(def.played, doc, record)
                if not playedOk then
                    printf("EotW gauntlet: custom event '%s' failed to mark itself: %s", tostring(def.id), tostring(err))
                end
            end
            return { eventId = def.id, record = record }
        end
    end
    return nil
end

--The section a played event plays, built from its text. Cached per client:
--every client builds the same entry from the same saved record.
local g_eventEntries = {}

local function EventEntry(pointId, played)
    local def = g_events[played.eventId or ""]
    if def == nil then
        return nil
    end
    local key = string.format("%s|%s|%s", tostring(pointId), tostring(played.eventId), json(played.record or {}))
    if g_eventEntries[key] ~= nil then
        return g_eventEntries[key]
    end
    local entry = nil
    local ok, err = pcall(function()
        local parsed = EncounterScript.Parse(def.text(played.record))
        local beat = parsed.beats[1]
        entry = beat ~= nil and EncounterScript.GauntletSections(beat)[1] or nil
    end)
    if not ok or entry == nil then
        printf("EotW gauntlet: could not build custom event '%s': %s", tostring(played.eventId), tostring(err))
        return nil
    end
    --no "/" in an id (it is a document key).
    entry.id = string.format("%s--%s", pointId, played.eventId)
    entry.gauntletEvent = true
    entry.eventPoint = pointId
    if def.adjust ~= nil then
        local adjustOk, adjustErr = pcall(def.adjust, entry, played.record)
        if not adjustOk then
            printf("EotW gauntlet: custom event '%s' adjust failed: %s", tostring(played.eventId), tostring(adjustErr))
        end
    end
    g_eventEntries[key] = entry
    return entry
end

--Put the sections of the events this Gauntlet has played into its parsed
--beat, so FindEntry finds them (EncounterMontage.FindMapScript calls this on
--every read of the script, like the montage's assassin threats).
local function AddEventEntries(beat, m)
    local round = (beat.rounds or {})[1]
    if round == nil then
        return
    end
    for i = #round.entries, 1, -1 do
        if round.entries[i].gauntletEvent then
            table.remove(round.entries, i)
        end
    end
    local g = type(m) == "table" and m.gauntlet or nil
    for pointId, played in pairs((g ~= nil and g.events) or {}) do
        if type(played) == "table" then
            local entry = EventEntry(pointId, played)
            if entry ~= nil then
                round.entries[#round.entries + 1] = entry
            end
        end
    end
end

function EncounterGauntlet.InjectEvents(script)
    local beats = (script ~= nil and script.parse ~= nil and script.parse.beats) or {}
    local m = EncounterMontage.GetDoc().data.montage
    for i, beat in ipairs(beats) do
        if beat.gauntlet then
            AddEventEntries(beat, (type(m) == "table" and m.beatIndex == i) and m or nil)
        end
    end
end

--- reading the state --------------------------------------------------------------

function EncounterGauntlet.GetState()
    local m = EncounterMontage.GetState()
    return m ~= nil and m.gauntlet or nil
end

--The section on the board right now (a custom event's entry while one
--plays), or nil.
function EncounterGauntlet.CurrentSection(beat, m)
    local g = m ~= nil and m.gauntlet or nil
    if g == nil or g.section == nil or beat == nil then
        return nil
    end
    return EncounterScript.FindEntry(beat, g.section)
end

--How many rolls this hero has made in the Gauntlet (the fatigue count).
function EncounterGauntlet.RollsMade(m, charid)
    local g = m ~= nil and m.gauntlet or nil
    return tonumber(((g ~= nil and g.rolls) or {})[charid or ""]) or 0
end

local function CountRoll(m, charid)
    if charid == nil or m.gauntlet == nil then
        return
    end
    m.gauntlet.rolls = m.gauntlet.rolls or {}
    m.gauntlet.rolls[charid] = (tonumber(m.gauntlet.rolls[charid]) or 0) + 1
end

--Who can take an option, for the stage and the host. Returns
--  { secret = bool,          -- an Allow rider gates it
--    allowed = { hero, ... },-- heroes who may claim it (all, if not secret)
--    knack = { hero, ... } } -- heroes who would take a better version
--`heroes` is EncounterMontage.Heroes().
function EncounterGauntlet.OptionHeroes(option, heroes)
    local result = { secret = EncounterScript.OptionIsSecret(option), allowed = {}, knack = {} }
    for _, hero in ipairs(heroes or {}) do
        local verdict = EncounterMontage.RiderVerdict(hero.charid, option, nil)
        if verdict == nil or verdict.allowed then
            result.allowed[#result.allowed + 1] = hero
        end
        if EncounterMontage.KnackIndex(hero.charid, option) ~= nil then
            result.knack[#result.knack + 1] = hero
        end
    end
    return result
end

--Is the option on show? A secret option only when a hero present may take
--it; then everyone sees it.
function EncounterGauntlet.OptionVisible(option, heroes)
    local who = EncounterGauntlet.OptionHeroes(option, heroes)
    return not who.secret or #who.allowed > 0
end

--- entering sections (host) -----------------------------------------------------

--The beat is over: the summary stays up for the montage's usual linger.
local function Finish(m)
    m.turn = nil
    m.gauntlet.section = nil
    m.gauntlet.vote = nil
    m.lastApplied = M().LastTurnResult(m)
    m.phase = "done"
    m.doneAt = Now()
    printf("EotW gauntlet: complete (%d sections met)", #(m.gauntlet.path or {}))
end

--Does any hero present speak `language`? The arrival scene belongs to the
--whole party, so a line is clear if anyone understands it.
local function AnyHeroSpeaks(heroes, language)
    for _, hero in ipairs(heroes) do
        if EncounterMontage.HeroSpeaks({ heroid = hero.charid }, language) then
            return true
        end
    end
    return false
end

--Build a section's arrival scene onto turn `t` (the shape BuildScenePart
--gives a montage scene, with no hero on the left). Returns how many lines
--it plays. The parser has already removed every line that needs PC.
local function BuildArrival(m, t, section, heroes)
    local env = {
        tier = nil,
        actors = section.actors or {},
        speaks = function(language)
            return AnyHeroSpeaks(heroes, language)
        end,
        test = function(atom)
            if EncounterScript.IsStoryAtom(atom) then
                return EncounterScript.EvalStoryAtom(atom, EncounterMontage.Story()) == true
            end
            return false
        end,
    }
    local cast = {}
    local steps = EncounterScript.FlattenScene(section.scene, env, cast)
    for _, step in ipairs(steps) do
        step.line = nil
        for _, e in ipairs(step.emotes or {}) do
            e.side = "right"
        end
        if step.kind == "say" then
            step.side = "right"
            if step.lang ~= nil and not env.speaks(step.lang) then
                step.plain = step.text
                step.text = EncounterScript.Garble(step.text, step.lang)
                step.garbled = true
            end
        end
    end
    m.seq = (m.seq or 0) + 1
    t.scene = { id = m.seq, part = "arrival", steps = steps, cast = cast }
    return #steps
end

--Put `section` on the board (nil: the Gauntlet is over). A custom event
--point plays its event, or passes the party straight through to its exit.
local function EnterSection(m, doc, beat, section, heroes)
    local g = m.gauntlet
    g.vote = nil
    g.eventPoint = nil
    m.turn = nil
    local guard = 0
    while section ~= nil and section.kind == "event" do
        guard = guard + 1
        if guard > #EncounterScript.GauntletSections(beat) + 1 then
            section = nil
            break
        end
        local played = ChooseEvent(doc, heroes)
        g.events = g.events or {}
        if played ~= nil then
            g.events[section.id] = played
            AddEventEntries(beat, m)
            local entry = EventEntry(section.id, played)
            if entry ~= nil then
                printf("EotW gauntlet: custom event '%s' plays at '%s'", tostring(played.eventId), tostring(section.name))
                g.eventPoint = section.id
                section = entry
                break
            end
        else
            g.events[section.id] = false
        end
        g.skipped = g.skipped or {}
        g.skipped[#g.skipped + 1] = section.id
        section = EncounterScript.GauntletNext(beat, section, nil, nil, #heroes)
    end
    if section == nil then
        Finish(m)
        return
    end

    g.section = section.id
    g.path = g.path or {}
    g.path[#g.path + 1] = section.id
    printf("EotW gauntlet: the party reaches '%s'", tostring(section.name))

    if section.scripted and section.scene ~= nil and #section.scene > 0 then
        m.seq = (m.seq or 0) + 1
        local t = {
            seq = m.seq,
            gauntlet = true,
            arrival = true,
            entryId = section.id,
            status = "scene",
            sceneAfter = "board",
            startedAt = Now(),
        }
        if BuildArrival(m, t, section, heroes) > 0 then
            m.turn = t
        end
    end
    if section.kind == "choice" then
        g.vote = { sectionId = section.id, choices = {}, startedAt = Now() }
    end
end

--Host, as the party arrives at the beat (EncounterMontage.HostTick): seed
--the state and put the first section up. Inside an open change of `doc`.
function EncounterGauntlet.Open(m, doc, beat, heroes)
    m.gauntlet = { path = {}, skipped = {}, rolls = {}, events = {}, ritualUsed = {} }
    --no party-size draw in a Gauntlet; an empty one stops the montage from
    --ever making one.
    m.removed = {}
    m.removedForPartySize = #heroes
    EnterSection(m, doc, beat, EncounterScript.GauntletFirst(beat, #heroes), heroes)
end

--A vote option's rules, aimed at the whole party (the narrative's rule for
--a choice made together).
local function PartyScoped(effects)
    local result = {}
    for _, effect in ipairs(effects or {}) do
        local copy = {}
        for k, v in pairs(effect) do
            copy[k] = v
        end
        if copy.target ~= nil then
            copy.target = "party"
        end
        result[#result + 1] = copy
    end
    return result
end

--The section the party goes to after `section` resolved with `option` (nil:
--nothing taken), whose landed effects were `effects`; nil is the end. A
--custom event point may come back here: it is only settled on arrival.
local function NextAfter(beat, m, section, option, effects, partySize)
    local g = m.gauntlet or {}
    local from = section
    local routeOption = option
    if section ~= nil and section.gauntletEvent then
        --an event leaves by its point's exit; its own options never route.
        from = EncounterScript.FindGauntletSection(beat, section.eventPoint or g.eventPoint)
        routeOption = nil
    end
    if from == nil then
        return nil
    end
    return EncounterScript.GauntletNext(beat, from, routeOption, EncounterScript.GotoTarget(effects), partySize)
end

local function MoveOn(m, doc, beat, heroes, section, option, effects)
    EnterSection(m, doc, beat, NextAfter(beat, m, section, option, effects, #heroes), heroes)
end

--For the stage: where the party is about to go, once the section on the
--board has its result (a resolved test or a settled vote). Returns
--  nil, false          -- nothing has resolved yet
--  section, true       -- the next section (it may be a custom event point)
--  nil, true           -- the end of the Gauntlet
function EncounterGauntlet.UpcomingSection(beat, m)
    local g = m ~= nil and m.gauntlet or nil
    if g == nil or beat == nil then
        return nil, false
    end
    local partySize = #EncounterMontage.Heroes()
    local section = EncounterGauntlet.CurrentSection(beat, m)
    local t = m.turn
    if t ~= nil and t.gauntlet and not t.arrival and t.status == "resolved" then
        local entry = EncounterMontage.TurnEntry(beat, t) or section
        local version = EncounterMontage.TurnOption(entry, t)
        local base = EncounterMontage.TurnBaseOption(entry, t)
        return NextAfter(beat, m, entry, base, EncounterMontage.VersionEffects(version, t.tier), partySize), true
    end
    local vote = g.vote
    if section ~= nil and vote ~= nil and vote.result ~= nil then
        local option = section.options[vote.result.optionIndex]
        return NextAfter(beat, m, section, option, PartyScoped((option ~= nil and option.free or {}).effects), partySize), true
    end
    return nil, false
end

--The backdrop while the party is at a section: its own [[scene]], else the
--beat's (a custom event's section uses its point's, then the beat's).
function EncounterGauntlet.SceneImage(script, beat)
    local m = EncounterMontage.GetState()
    local section = nil
    if m ~= nil and beat ~= nil and m.beatIndex ~= nil and script ~= nil and script.parse ~= nil
        and script.parse.beats[m.beatIndex] == beat then
        section = EncounterGauntlet.CurrentSection(beat, m)
        if section ~= nil and section.gauntletEvent then
            section = EncounterScript.FindGauntletSection(beat, section.eventPoint)
        end
    end
    if section ~= nil and section.sceneTag ~= nil then
        local image = EncounterMontage.SceneImage(script, section)
        if image ~= nil then
            return image
        end
    end
    return EncounterMontage.SceneImage(script, beat)
end

--- votes (host) -------------------------------------------------------------------

local function ResolveVote(m, doc, section, heroes, optionIndex, decidedBy)
    local g = m.gauntlet
    local option = section.options[optionIndex]
    if option == nil then
        return
    end
    local anchor = nil
    for _, hero in ipairs(heroes) do
        if decidedBy ~= nil and hero.ownerId == decidedBy and anchor == nil then
            anchor = hero
        end
    end
    anchor = anchor or heroes[1]
    local applied, newAllies = EncounterMontage.ApplyEffects(PartyScoped((option.free or {}).effects), {
        heroEntry = anchor,
        userid = anchor ~= nil and anchor.ownerId or nil,
        entryName = section.name,
        entryId = section.id,
        montage = m,
        --the whole party chose this, so its Intelligence is everyone's.
        splitIntelligence = true,
        doc = doc,
    })
    for _, charid in ipairs(newAllies or {}) do
        if anchor ~= nil then
            EncounterMontage.RecordAlly(doc, anchor.charid, charid)
        end
    end
    g.vote.result = {
        optionIndex = optionIndex,
        optionName = option.name,
        decidedBy = decidedBy,
        applied = applied,
        at = Now(),
    }
    g.vote.decision = g.vote.decision
    m.log = m.log or {}
    m.log[#m.log + 1] = {
        round = 1,
        choice = true,
        entryId = section.id,
        entryName = section.name,
        optionName = option.name,
        applied = applied,
        decidedBy = decidedBy,
    }
    EotwAnalytics.Track("eotw_gauntlet_vote", {
        beat = doc.data.beat,
        section = section.name,
        option = option.name,
        optionIndex = optionIndex,
        options = #section.options,
        split = decidedBy ~= nil,
        landed = #applied,
    })
    printf("EotW gauntlet: the party takes '%s' at '%s'", tostring(option.name), tostring(section.name))
end

--A split vote: a random voter decides; every client flashes across the
--candidates until startedAt + the narrative's flash time.
local function BeginDecision(m, section, heroes)
    local vote = m.gauntlet.vote
    local candidates = {}
    for _, voter in ipairs(EncounterNarrative.Voters(section, heroes)) do
        local choice = (vote.choices or {})[voter.key]
        if choice ~= nil then
            local option = section.options[choice.optionIndex]
            candidates[#candidates + 1] = {
                key = voter.key,
                name = voter.name,
                optionIndex = choice.optionIndex,
                optionName = option ~= nil and option.name or "?",
                heroids = voter.heroids,
            }
        end
    end
    if #candidates == 0 then
        return false
    end
    local winner = candidates[math.random(#candidates)]
    vote.decision = {
        candidates = candidates,
        winner = winner.key,
        winnerName = winner.name,
        optionIndex = winner.optionIndex,
        optionName = winner.optionName,
        startedAt = Now(),
    }
    printf("EotW gauntlet: the party is split; %s decides (%s)", tostring(winner.name), tostring(winner.optionName))
    return true
end

--Advance a vote: settle it once everyone has voted, land a decision once
--its flash has run, and move on once its result has been read.
local function TickVote(m, doc, beat, section, heroes)
    local vote = m.gauntlet.vote
    if vote.result ~= nil then
        local linger = cond(#(vote.result.applied or {}) > 0, RESULT_LINGER_SECONDS, RESULT_LINGER_QUIET)
        if Now() - (tonumber(vote.result.at) or 0) >= linger then
            local option = section.options[vote.result.optionIndex]
            MoveOn(m, doc, beat, heroes, section, option, PartyScoped((option ~= nil and option.free or {}).effects))
        end
        return
    end
    if vote.decision ~= nil then
        local flash = EncounterNarrative.DECIDE_FLASH_SECONDS or 3.2
        if Now() - (tonumber(vote.decision.startedAt) or 0) >= flash then
            ResolveVote(m, doc, section, heroes, vote.decision.optionIndex, vote.decision.winner)
        end
        return
    end
    local voters = EncounterNarrative.Voters(section, heroes)
    if #voters == 0 then
        return
    end
    local first, split = nil, false
    for _, voter in ipairs(voters) do
        local choice = (vote.choices or {})[voter.key]
        if choice == nil then
            return
        end
        if first == nil then
            first = choice.optionIndex
        elseif choice.optionIndex ~= first then
            split = true
        end
    end
    if split and BeginDecision(m, section, heroes) then
        return
    end
    ResolveVote(m, doc, section, heroes, first or 1, nil)
end

--- the host tick ------------------------------------------------------------------

--Host, every montage tick while the Gauntlet plays (EncounterMontage.HostTick,
--inside its open change).
function EncounterGauntlet.HostTick(m, doc, beat, heroes)
    if m.gauntlet == nil then
        EncounterGauntlet.Open(m, doc, beat, heroes)
        return
    end
    local section = EncounterGauntlet.CurrentSection(beat, m)
    if section == nil then
        if m.gauntlet.section ~= nil then
            --the section vanished (the script changed under the party).
            printf("EotW gauntlet: section '%s' is gone from the script; ending the Gauntlet", tostring(m.gauntlet.section))
        end
        Finish(m)
        return
    end
    local t = m.turn

    --a claimed assist that is never rolled: the claim is handed back (the
    --hero making the test can go on without it).
    if t ~= nil and t.status == "assisting" and t.assist ~= nil then
        if Now() - (tonumber(t.assist.startedAt) or Now()) >= ASSIST_ROLL_SECONDS then
            printf("EotW gauntlet: %s never rolled their assist; the claim is handed back", tostring(t.assist.heroName))
            t.assist = nil
            t.status = "assist"
        end
    end

    --a test (or No Roll option) has resolved: once its result has been
    --read, on to the next section.
    if t ~= nil and t.gauntlet and not t.arrival and t.status == "resolved" then
        local linger = cond(#(t.applied or {}) > 0, RESULT_LINGER_SECONDS, RESULT_LINGER_QUIET)
        if Now() - (tonumber(t.resolvedAt) or 0) >= linger then
            local entry = EncounterMontage.TurnEntry(beat, t)
            local version = EncounterMontage.TurnOption(entry, t)
            local base = EncounterMontage.TurnBaseOption(entry, t)
            MoveOn(m, doc, beat, heroes, entry or section, base, EncounterMontage.VersionEffects(version, t.tier))
        end
        return
    end

    if m.turn == nil and section.kind == "choice" and m.gauntlet.vote ~= nil then
        TickVote(m, doc, beat, section, heroes)
    end
end

--- requests (host) ----------------------------------------------------------------

local IGNORED_IN_GAUNTLET = { approach = true, pass = true, backout = true, choose = true, continue = true }

--Handle a request in a Gauntlet beat. Returns handled (false: the montage
--handles it as usual) and a line for the log.
function EncounterGauntlet.HandleRequest(m, doc, userid, req, beat, heroes)
    local kind = req.kind
    local g = m.gauntlet
    local t = m.turn
    local I = M()

    if IGNORED_IN_GAUNTLET[kind] then
        return true, string.format("ignored %s: there is no such step in a Gauntlet", tostring(kind))
    end

    --fatigue: a roll that is about to land counts against its roller. The
    --montage still handles the request itself.
    if kind == "rolled" then
        if t ~= nil and t.gauntlet and t.status == "rolling" and t.userid == userid and t.rollSeq == req.rollSeq then
            CountRoll(m, t.heroid)
        end
        return false
    elseif kind == "pardonRolled" then
        local p = t ~= nil and t.pardon or nil
        if t ~= nil and t.gauntlet and t.status == "pardon" and p ~= nil and p.userid == userid and p.rollSeq == req.rollSeq then
            CountRoll(m, p.heroid)
        end
        return false
    end

    local gauntletKinds = { claim = true, unclaim = true, cancel = true, assist = true, assistRolled = true,
        assistCancel = true, proceedTest = true, bless = true, vote = true, unvote = true }
    if not gauntletKinds[kind] then
        return false
    end
    if g == nil or m.phase ~= "rounds" then
        return true, string.format("ignored %s: the Gauntlet is not under way", tostring(kind))
    end
    local section = EncounterGauntlet.CurrentSection(beat, m)
    if section == nil then
        return true, string.format("ignored %s: no section on the board", tostring(kind))
    end

    if kind == "claim" then
        if t ~= nil then
            return true, "ignored claim: an option is already being taken (or the party is still arriving)"
        end
        if section.kind == "choice" then
            return true, "ignored claim: this section is a vote"
        end
        local hero = I.HeroByCharid(heroes, req.heroid)
        if hero == nil or not I.UserControlsHero(userid, hero) then
            return true, "ignored claim: not your hero"
        end
        local index = tonumber(req.optionIndex)
        local option = index ~= nil and section.options[index] or nil
        if option == nil then
            return true, "ignored claim: no such option"
        end
        m.seq = (m.seq or 0) + 1
        m.turn = {
            seq = m.seq,
            gauntlet = true,
            userid = userid,
            heroid = hero.charid,
            heroName = hero.name,
            entryId = section.id,
            status = "choosing",
            startedAt = Now(),
        }
        local line = I.ChooseOption(m, doc, m.turn, beat, index, heroes, userid)
        if m.turn ~= nil and m.turn.status == "choosing" then
            --refused (a secret option this hero does not qualify for, ...):
            --the board stays open.
            m.turn = nil
        end
        return true, line
    end

    if kind == "vote" or kind == "unvote" then
        local vote = g.vote
        if section.kind ~= "choice" or vote == nil or t ~= nil then
            return true, "ignored vote: not voting"
        end
        if vote.decision ~= nil or vote.result ~= nil then
            return true, "ignored vote: the vote is settled"
        end
        local key = EncounterNarrative.VoterKeyForUser(userid, heroes)
        if key == nil then
            return true, "ignored vote: controls no hero"
        end
        vote.choices = vote.choices or {}
        if kind == "unvote" then
            vote.choices[key] = nil
            return true, string.format("%s took their vote back", tostring(key))
        end
        local index = tonumber(req.optionIndex)
        if index == nil or section.options[index] == nil then
            return true, "ignored vote: no such option"
        end
        vote.choices[key] = { optionIndex = index, userid = userid, at = Now() }
        return true, string.format("%s votes for '%s'", tostring(key), section.options[index].name)
    end

    --everything below acts on the claimed turn.
    if t == nil or not t.gauntlet or t.arrival then
        return true, string.format("ignored %s: no option is being taken", tostring(kind))
    end

    if kind == "unclaim" then
        if t.userid ~= userid then
            return true, "ignored unclaim: not your claim"
        end
        local early = (t.status == "scene" and t.scene ~= nil and t.scene.part == "option") or t.status == "assist"
        if not early then
            return true, "ignored unclaim: too late to step back"
        end
        m.turn = nil
        return true, string.format("%s steps back from %s", tostring(t.heroName), tostring(t.optionName))
    elseif kind == "cancel" then
        --the roll dialog closed before the dice were thrown: back to the
        --assist step, where the hero can step back or try again.
        if t.userid ~= userid or t.status ~= "rolling" or t.rollSeq ~= req.rollSeq then
            return true, "ignored cancel"
        end
        t.status = "assist"
        t.rollSeq = nil
        return true, "roll cancelled"
    elseif kind == "assist" then
        if t.status ~= "assist" then
            return true, "ignored assist: not the moment"
        end
        if t.assist ~= nil then
            return true, "ignored assist: someone is already assisting"
        end
        local hero = I.HeroByCharid(heroes, req.heroid)
        if hero == nil or not I.UserControlsHero(userid, hero) then
            return true, "ignored assist: not your hero"
        end
        if hero.charid == t.heroid then
            return true, "ignored assist: a hero cannot assist their own test"
        end
        m.seq = (m.seq or 0) + 1
        t.assist = {
            userid = userid,
            heroid = hero.charid,
            heroName = hero.name,
            rollSeq = m.seq,
            startedAt = Now(),
        }
        t.status = "assisting"
        return true, string.format("%s steps in to assist %s", hero.name, tostring(t.heroName))
    elseif kind == "assistRolled" or kind == "assistCancel" then
        local a = t.assist
        if a == nil or t.status ~= "assisting" or a.userid ~= userid or a.rollSeq ~= req.rollSeq then
            return true, "ignored assist roll: stale"
        end
        if kind == "assistCancel" then
            t.assist = nil
            t.status = "assist"
            return true, string.format("%s does not assist after all", tostring(a.heroName))
        end
        local tier = math.max(1, math.min(3, math.floor(tonumber(req.tier) or 1)))
        ---@type string|nil
        local outcome = ASSIST_OUTCOMES[tier]
        if tier == 1 and EncounterMontage.HeroHasPerk(a.heroid, "Put Your Back Into It!") then
            outcome = nil
        end
        a.tier = tier
        a.total = req.total
        a.outcome = outcome
        CountRoll(m, a.heroid)
        t.status = "assist"
        return true, string.format("%s assists %s: tier %d (%s)", tostring(a.heroName), tostring(t.heroName), tier, tostring(outcome or "no effect"))
    elseif kind == "proceedTest" then
        if t.userid ~= userid or t.status ~= "assist" then
            return true, "ignored proceed: not the moment"
        end
        I.StartRoll(m, t)
        return true, string.format("%s makes the test", tostring(t.heroName))
    elseif kind == "bless" then
        --Ritualist: the hero taking the test blesses it before the roll,
        --once per Gauntlet (decision taken while building; easy to change).
        if t.status ~= "assist" or t.blessing ~= nil then
            return true, "ignored bless: not the moment"
        end
        local hero = I.HeroByCharid(heroes, req.heroid)
        if hero == nil or not I.UserControlsHero(userid, hero) or hero.charid ~= t.heroid then
            return true, "ignored bless: only the hero taking the test can bless it"
        end
        g.ritualUsed = g.ritualUsed or {}
        if not EncounterMontage.HeroHasPerk(hero.charid, "Ritualist") or g.ritualUsed[hero.charid] then
            return true, "ignored bless: no blessing to give"
        end
        g.ritualUsed[hero.charid] = true
        t.blessing = { heroid = hero.charid, heroName = hero.name }
        return true, string.format("%s blesses their own test (Ritualist)", hero.name)
    end
    return false
end

--Host: the chosen test is about to be rolled (EncounterMontage's
--BeginTest). The characteristic is fixed here so the assist rolls the one
--the test will, then the turn waits for an assist or "Make the test". A
--party of one has nobody to wait for.
function EncounterGauntlet.BeginAssist(m, t, beat)
    local entry = EncounterMontage.TurnEntry(beat, t)
    local option = EncounterMontage.TurnOption(entry, t)
    t.assist = nil
    t.testAttrid = nil
    if option ~= nil and option.roll ~= nil then
        pcall(function() t.testAttrid = EncounterMontage.TestCharacteristic(t.heroid, option) end)
    end
    t.status = "assist"
    if #EncounterMontage.Heroes() <= 1 then
        M().StartRoll(m, t)
    end
end

--- rolls (client) -----------------------------------------------------------------

--The Weary chip for `charid` (every roll they have already made in this
--Gauntlet is a bane; Draw Steel caps it at a double bane) and, when
--`includeAssist`, the assist's edge or bane. Appends to `modifiers`.
function EncounterGauntlet.AppendRollModifiers(modifiers, turn, charid, includeAssist)
    local I = M()
    local n = EncounterGauntlet.RollsMade(EncounterMontage.GetState(), charid)
    local chip = nil
    if n == 1 then
        chip = I.PerkChip(T("gauntlet.chip.weary_one"), T("gauntlet.chip.weary_description"), "bane")
    elseif n >= 2 then
        chip = I.PerkChip(T("gauntlet.chip.weary_many", { count = n }), T("gauntlet.chip.weary_description"), "double_bane")
    end
    if chip ~= nil then
        modifiers[#modifiers + 1] = chip
    end
    local a = includeAssist and turn ~= nil and turn.assist or nil
    if a ~= nil and a.outcome ~= nil then
        local modtype = ASSIST_MODTYPES[a.outcome]
        local args = { hero = a.heroName or T("gauntlet.chip.assist_fallback"), tier = a.tier or 1 }
        local label
        if a.outcome == "bane" then
            label = T("gauntlet.chip.assist_bane", args)
        elseif a.outcome == "edge" then
            label = T("gauntlet.chip.assist_edge", args)
        else
            label = T("gauntlet.chip.assist_doubleedge", args)
        end
        local assistChip = I.PerkChip(label, T("gauntlet.chip.assist_description", args), modtype)
        if assistChip ~= nil then
            modifiers[#modifiers + 1] = assistChip
        end
    end
    return modifiers
end

--the assist roll this client has launched, so it is shown once.
local m_launchedAssistSeq = nil

--Show the assist roll to the assister's player: the test's characteristic,
--Skilled +2 for a listed skill they are trained in, their own features and
--fatigue, on the fixed assist table (bane / edge / double edge).
local function LaunchAssistRoll(t, option, token)
    local I = M()
    local a = t.assist
    local c = token.properties
    local _, skills = EncounterScript.ParseAttr(option.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
    local attrid = t.testAttrid or EncounterMontage.TestCharacteristic(token.charid, option)
    local modifier = 0
    if attrid ~= nil then
        local attr = c:GetAttribute(attrid)
        if attr ~= nil then
            modifier = attr:Modifier()
        end
    end
    local title = T("gauntlet.assist.roll_title", { hero = t.heroName or T("gauntlet.chip.assist_fallback"), test = option.roll.name })
    local rollType = "test_power_roll"
    local roll = string.format("2d10 + %d", modifier)
    local modifiers = {}
    if attrid ~= nil then
        modifiers = c:GetModifiersForPowerRoll(roll, rollType, { attribute = attrid, title = title, skills = skills })
    end
    I.ApplySkilledModifier(c, modifiers, skills)
    EncounterGauntlet.AppendRollModifiers(modifiers, t, token.charid, false)
    I.ShowMontageRoll {
        creature = c,
        heroToken = token,
        title = title,
        rollType = rollType,
        roll = roll,
        modifiers = modifiers,
        tiers = { T("gauntlet.assist.tier1"), T("gauntlet.assist.tier2"), T("gauntlet.assist.tier3") },
        rollSeq = a.rollSeq,
        expectedStatus = "assisting",
        CurrentRollSeq = function(turn) return (turn.assist or {}).rollSeq end,
        completeKind = "assistRolled",
        cancelKind = "assistCancel",
        onNotShown = function()
            m_launchedAssistSeq = nil
        end,
    }
end

--Client (EncounterMontage.ClientTick, while a turn is "assisting"): roll the
--assist if it is this user's.
function EncounterGauntlet.ClientTick(m, t)
    local a = t.assist
    if a == nil or a.userid ~= dmhub.loginUserid or a.tier ~= nil then
        return
    end
    if m_launchedAssistSeq == a.rollSeq then
        return
    end
    local beat = EncounterMontage.CurrentBeat()
    local entry = beat ~= nil and EncounterMontage.TurnEntry(beat, t) or nil
    local option = EncounterMontage.TurnOption(entry, t)
    local token = dmhub.GetCharacterById(a.heroid)
    if option == nil or option.roll == nil or token == nil or not token.valid then
        return
    end
    m_launchedAssistSeq = a.rollSeq
    LaunchAssistRoll(t, option, token)
end

--- Secret Twin's assassin (the first custom event) ---------------------------------
--
--A town respite can mark a Secret Twin hero (EncounterMontage's
--AssassinField). The montage sends the assassin as an extra threat; a
--Gauntlet sends it at its first custom event point, as an obstacle a hero
--must take on. doc.data.assassinsSent makes it once per game either way
--(and tells the town to clear the mark).
EncounterGauntlet.RegisterCustomEvent{
    id = "assassin",
    priority = 100,
    available = function(heroes, doc)
        local field = M().AssassinField
        local sent = doc.data.assassinsSent or {}
        for _, hero in ipairs(heroes) do
            local pending = false
            pcall(function() pending = hero.token.properties:try_get(field, false) == true end)
            if pending and not sent[hero.charid] then
                return { charid = hero.charid, name = hero.name }
            end
        end
        return nil
    end,
    played = function(doc, record)
        doc.data.assassinsSent = doc.data.assassinsSent or {}
        doc.data.assassinsSent[record.charid] = true
        printf("EotW gauntlet: an assassin hunts %s", tostring(record.name))
    end,
    text = function(record)
        local I = M()
        local heroName = I.AssassinHeroName(record.name)
        local consequence = T("montage.assassin.consequence", { hero = heroName })
        return table.concat({
            "# Gauntlet",
            "",
            "## " .. I.AssassinThreatName(record.name),
            "",
            T("montage.assassin.description", { hero = heroName }),
            "",
            "### " .. T("montage.assassin.option_name"),
            "",
            "|Ambush Test: Agility or Intuition (Alertness, Sneak)",
            --the teaser warns of the blade; the damage itself is the effect
            --added in `adjust`, rolled on the screen.
            string.format("|%s %s. => %s", T("montage.assassin.tier1"), consequence, T("montage.assassin.tier1")),
            "|You lose 3 stamina.",
            "|" .. T("gauntlet.assassin.driven_off"),
        }, "\n")
    end,
    adjust = function(entry, record)
        local option = entry.options[1]
        if option == nil or option.roll == nil then
            return
        end
        local heroName = M().AssassinHeroName(record.name)
        local effects = option.roll.effects[1] or {}
        effects[#effects + 1] = { kind = "damage", heroid = record.charid, dice = "4d6",
            label = T("montage.assassin.dice_label"), text = T("montage.assassin.consequence", { hero = heroName }) }
        option.roll.effects[1] = effects
    end,
}

--- dev --------------------------------------------------------------------------

--"/eotwgauntlet state": where the party is, the fatigue counts and the turn.
local function PrintState()
    local m = EncounterMontage.GetState()
    local g = m ~= nil and m.gauntlet or nil
    if g == nil then
        print("EotW gauntlet: no Gauntlet is running")
        return
    end
    --g is only set when m is.
    ---@cast m -nil
    local beat = EncounterMontage.CurrentBeat()
    local section = EncounterGauntlet.CurrentSection(beat, m)
    printf("EotW gauntlet: phase %s, section %s (%s)", tostring(m.phase), tostring(g.section),
        tostring(section ~= nil and section.kind or "?"))
    printf("  path: %s", table.concat(g.path or {}, " > "))
    for charid, n in pairs(g.rolls or {}) do
        local tok = dmhub.GetCharacterById(charid)
        printf("  rolls: %s %d", tostring(tok ~= nil and tok.name or charid), n)
    end
    local turn = m.turn
    if turn ~= nil then
        local helper = ""
        if turn.assist ~= nil then
            helper = ", assisted by " .. tostring(turn.assist.heroName)
        end
        printf("  turn: %s on %s, status %s%s", tostring(turn.heroName or "(arrival)"), tostring(turn.optionName),
            tostring(turn.status), helper)
    end
    if g.vote ~= nil then
        for key, choice in pairs(g.vote.choices or {}) do
            printf("  vote: %s -> option %s", tostring(key), tostring(choice.optionIndex))
        end
    end
end

pcall(function()
    Commands.RegisterMacro{
        name = "eotwgauntlet",
        summary = "inspect the Encounter of the Week Gauntlet beat",
        doc = "Usage: /eotwgauntlet state | json\nstate prints the section on the board, the path so far, each hero's roll count (fatigue) and the turn; json prints the raw state. Run a Gauntlet with /eotwmontage start (a Gauntlet is a montage beat).",
        command = function(str)
            local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
            if arg == "json" then
                print(json(EncounterGauntlet.GetState()))
            else
                PrintState()
            end
        end,
    }
end)
