local mod = dmhub.GetModLoading()

--Encounter of the Week: the narrative runtime on the montage engine (built
--as the Gauntlet, which folded into Narrative on 2026-11-07).
--
--A "# Narrative" beat is parsed into sections (EncounterScript.lua,
--"narrative sections", beat.gauntlet = true) and played by the montage
--runtime (EncounterMontage.lua), which calls in here at the few points where
--the rules differ. Design: GAUNTLET_PLAN.md at the dmhub repo root.
--
--How it plays: the party meets one section at a time.
--  * A CHALLENGE shows every option at once. Any player claims one for one
--    of their heroes ("claim"); the first claim wins. The claim becomes the
--    montage turn, which plays the option's own lines, then the ASSIST step
--    (one other hero may assist: "assist" / "assistRolled"), then the roll
--    once the claiming player presses Make the test ("proceedTest"), then
--    perks, dice and the outcome, exactly as a montage test does.
--  * A CHOICE ("Choose together:", or no marker and no test) is a party
--    vote, one per player (a split goes to a random voter). A section with
--    no options is a choice of one: the implicit Proceed.
--  * An INDIVIDUAL section ("Choose individually:") takes one choice per
--    hero; each option is applied once, for the heroes who took it.
--  * "Unlock: <Feature>" turns a feature on as its section arrives (the
--    beat's own lines as the beat starts) and hangs its explanation on the
--    stage until that section is decided (m.announce, ActiveAnnounce).
--  * A custom event point ("## Custom Event") plays the first registered
--    event that is ready (EncounterGauntlet.RegisterCustomEvent), or is
--    passed over silently.
--  * Every roll a hero makes in the beat (assists and Pardon My Friend
--    included) adds a bane to their later rolls in it ("Weary"); the count
--    starts again with the next beat.
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
--    vote      = nil | { sectionId, individual = bool,
--                  choices = { [voterKey] = { optionIndex, userid, heroid,
--                  at } }, -- voterKey: a userid (or "PARTY"), a hero
--                  charid in an individual section (EncounterNarrative.Voters)
--                  decision = nil | { candidates, winner,
--                  winnerName, optionIndex, optionName, startedAt },
--                  result = nil | { optionIndex, optionName, decidedBy,
--                  applied, at, groups = nil | { { optionIndex,
--                  optionName, heroNames, applied }, ... } } },
--    ritualUsed = { [charid] = true },  -- Ritualist: once per Gauntlet
--    lastClaim = nil | { heroid, userid, heroName }, -- who took the last
--                                          option of a challenge
--    spotlight = nil | { sectionId, heroid, userid, heroName, autoTried },
--                                       -- a "(Spotlight)" section on the
--                                          board: only this hero may take it
--    group = nil | { sectionId, startedAt, order = { charid, ... },
--                  heroes = { [charid] = { heroName, userid, rollSeq,
--                  status = "rolling"|"done", startedAt, tier, total,
--                  tierText, applied, knackReason, auto } },
--                  result = nil | { at, applied = n } },
--                                       -- an "Everyone rolls:" section: every
--                                          hero makes its test at once
--    cast = nil | { { name, monster }, ... }, -- the characters on stage after
--                                          the latest scene part (arrival or
--                                          option lines). They stay on the
--                                          right through later sections until
--                                          an "exits" line or the beat ends.
--    heroEmote = nil | { heroid, emote, seq, part }, -- the hero's last
--                                          "alert" / "alarmed" (an interrupted
--                                          roll sets "alarmed"); held on their
--                                          portrait until a test of theirs
--                                          lands (not one whose own outcome
--                                          lines, part "outcome", gave it)
--  }
--  m.announce = nil | { feature, name, text, at, sectionId } -- a feature
--    that just arrived (sectionId nil: the beat's own line).
--  turn.gauntlet = true on every turn a Gauntlet makes. turn.arrival = true
--  on the turn that only plays a section's arrival scene (no hero). The
--  assist rides on the turn:
--  turn.assist = nil | { userid, heroid, heroName, rollSeq, startedAt,
--                        tier, total, outcome = "bane"|"edge"|"doubleedge"|nil }
--  turn.testAttrid = the characteristic the test (and so the assist) uses.

EncounterGauntlet = rawget(_G, "EncounterGauntlet") or {}

local T = UIText.T

--Is the narrative beat at `index` the one the montage state is playing?
--(Across a handover the previous beat's state is briefly still there.)
function EncounterGauntlet.RunsNarrative(index)
    local m = EncounterMontage.GetState()
    if m == nil or index == nil or m.beatIndex ~= index then
        return false
    end
    local script = EncounterMontage.FindMapScript()
    local beat = script ~= nil and script.parse ~= nil and script.parse.beats[index] or nil
    return beat ~= nil and beat.kind == "narrative"
end

--how long a section's result stays on screen before the party moves on.
local RESULT_LINGER_SECONDS = 4
--the same, for a test result that applied nothing (its roll is still worth
--a look).
local RESULT_LINGER_QUIET = 1.5
--and for a choice that applied nothing (a plain "Proceed"): turning a page,
--not waiting out a timer.
local CHOICE_LINGER_QUIET = 0.4
--a claimed assist that is never rolled is handed back after this long.
local ASSIST_ROLL_SECONDS = 300
--an "Everyone rolls:" hero whose player never rolls is rolled for by the
--host after this long, so one absent player cannot stall the party.
local GROUP_ROLL_SECONDS = 240
--an interrupted test has no result worth reading: its lines were the
--result, so the party moves on in the same host change that ends them (no
--"resolved" screen flashes past between the scene and the next section).
local RESULT_LINGER_INTERRUPTED = 0

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
--  text      function(record) -> the event as script text: a
--            "# Narrative" heading and ONE "## <Name>" section.
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

--Put the sections of the events this beat has played into its parsed beat
--(beat.eventEntries, beside its sections, so routing never sees them) where
--FindEntry finds them. EncounterMontage.FindMapScript calls this on every
--read of the script, like the montage's assassin threats.
local function AddEventEntries(beat, m)
    beat.eventEntries = {}
    local g = type(m) == "table" and m.gauntlet or nil
    for pointId, played in pairs((g ~= nil and g.events) or {}) do
        if type(played) == "table" then
            local entry = EventEntry(pointId, played)
            if entry ~= nil then
                beat.eventEntries[#beat.eventEntries + 1] = entry
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

--The section the party met last (the end of its path), or nil. Once the
--beat is done there is no section on the board, but its end screen keeps
--the last one's name and scene.
function EncounterGauntlet.LastSection(beat, m)
    local path = (m ~= nil and m.gauntlet or {}).path or {}
    if beat == nil or #path == 0 then
        return nil
    end
    return EncounterScript.FindEntry(beat, path[#path])
end

--- who is on stage ---------------------------------------------------------------
--Characters who have entered and not exited stay on the right of the stage
--through the sections after the scene that brought them on (the board and
--the claimed test screens), until an "exits" line or the end of the beat.
--The host keeps them in g.cast so every client shows the same cast.

--A plain copy of a cast list ({ { name, monster }, ... }); nil -> {}.
function EncounterGauntlet.CopyCast(cast)
    local copy = {}
    for i, c in ipairs(cast or {}) do
        copy[i] = { name = c.name, monster = c.monster }
    end
    return copy
end

--The characters on stage in this beat right now (never nil).
function EncounterGauntlet.Cast(m)
    local g = m ~= nil and m.gauntlet or nil
    return (g ~= nil and g.cast) or {}
end

--The emote held on hero `heroid`'s portrait ("alert" / "alarmed"), or nil.
function EncounterGauntlet.HeldEmote(m, heroid)
    local held = m ~= nil and m.gauntlet ~= nil and m.gauntlet.heroEmote or nil
    if type(held) ~= "table" or heroid == nil or held.heroid ~= heroid then
        return nil
    end
    return held.emote
end

--Emotes that can be held on a portrait ("scared" is a shake, not a mark).
local HELD_EMOTES = { alert = true, alarmed = true }

--The last holdable emote on the hero (the left side) in a built scene
--part, or nil.
local function LastHeroEmote(scene)
    local found = nil
    for _, step in ipairs((scene or {}).steps or {}) do
        for _, e in ipairs(step.emotes or {}) do
            if e.side == "left" and HELD_EMOTES[e.emote] then
                found = e.emote
            end
        end
    end
    return found
end

--Host: turn `t`'s scene part has been read to the end. Its last emote on
--the hero is held from now on.
function EncounterGauntlet.NoteSceneEnded(m, t)
    if m.gauntlet == nil or t == nil or t.heroid == nil then
        return
    end
    local emote = LastHeroEmote(t.scene)
    if emote ~= nil then
        m.gauntlet.heroEmote = { heroid = t.heroid, emote = emote, seq = t.seq, part = (t.scene or {}).part }
    end
end

--Host: the roll on turn `t` was interrupted and its lines are built. The
--roller is alarmed from that moment on, unless the author wrote an emote
--for PC in those lines (theirs is held once read: NoteSceneEnded).
function EncounterGauntlet.NoteInterrupted(m, t)
    if m.gauntlet == nil or t == nil or t.heroid == nil then
        return
    end
    if t.status == "scene" and LastHeroEmote(t.scene) ~= nil then
        return
    end
    m.gauntlet.heroEmote = { heroid = t.heroid, emote = "alarmed", seq = t.seq }
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

--- unlocks ----------------------------------------------------------------------

--"Unlock: Intelligence" on `holder` (the beat, or a section as it arrives):
--turn the feature on, and announce one that just arrived so the stage shows
--its explanation and the strip blinks its pool. Host, inside an open change
--of `doc`; `m` is doc.data.montage.
function EncounterGauntlet.ApplyUnlocks(m, doc, holder, sourceName, sectionId)
    for _, u in ipairs((holder or {}).unlocks or {}) do
        if EncounterMontage.UnlockFeature(doc, u.feature, sourceName) then
            printf("EotW narrative: %s is unlocked (%s)", tostring(u.name), tostring(sourceName))
            local record = EncounterScript.FEATURES[u.feature]
            if record ~= nil and record.explanation ~= nil then
                m.announce = {
                    feature = u.feature,
                    name = record.name,
                    text = record.explanation,
                    at = Now(),
                    sectionId = sectionId,
                }
            end
        end
    end
end

--Has the section on the board been decided (a test resolved, a choice
--settled)? Until then its callout stays up.
local function SectionDecided(m)
    local t = m.turn
    if t ~= nil and t.gauntlet and not t.arrival and t.status == "resolved" then
        return true
    end
    local vote = m.gauntlet ~= nil and m.gauntlet.vote or nil
    return vote ~= nil and (vote.result ~= nil or vote.decision ~= nil)
end

--The feature callout that should be on screen, or nil: from the moment it
--arrives until the party has decided the section it arrived with (the
--beat's own line: the first section).
function EncounterGauntlet.ActiveAnnounce(m)
    local announce = m ~= nil and m.announce or nil
    if type(announce) ~= "table" or announce.text == nil then
        return nil
    end
    ---@cast m -nil
    if m.phase == "arriving" then
        return announce
    end
    if m.phase ~= "rounds" or SectionDecided(m) then
        return nil
    end
    return announce
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
    --whoever is still on stage from earlier sections starts the scene; its
    --entrances and exits carry on to the sections after it (even an
    --arrival of nothing but "X exits", which plays no line).
    local cast = EncounterGauntlet.CopyCast(m.gauntlet.cast)
    local steps = EncounterScript.FlattenScene(section.scene, env, cast)
    m.gauntlet.cast = EncounterGauntlet.CopyCast(cast)
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
    --the last section's callout goes with it; the beat's own stays for the
    --first section.
    if #(g.path or {}) > 0 then
        m.announce = nil
    end
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
    --"(Spotlight)": the hero who took the last test must take this one too
    --(if they are still here; else anyone may, as in any challenge).
    g.spotlight = nil
    g.group = nil
    if section.spotlight and g.lastClaim ~= nil then
        local hero = M().HeroByCharid(heroes, g.lastClaim.heroid)
        if hero ~= nil then
            g.spotlight = { sectionId = section.id, heroid = hero.charid, userid = g.lastClaim.userid, heroName = hero.name }
        end
    end
    --whatever the section unlocks arrives with it.
    EncounterGauntlet.ApplyUnlocks(m, doc, section, section.name, section.id)

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
    if section.kind == "choice" or section.kind == "individual" then
        g.vote = { sectionId = section.id, individual = section.kind == "individual", choices = {}, startedAt = Now() }
    end
    --a spotlight section with one way through is claimed in this same host
    --change, so the board never flashes up for a tick before the claim.
    if m.turn == nil and section.kind == "challenge" then
        EncounterGauntlet.SpotlightAutoClaim(m, doc, beat, section, heroes)
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

--The option a settled choice leaves by and the effects whose "go to" counts:
--a vote's option (aimed at the party); an individual section leaves by its
--own exit (each hero took their own way, so no option routes).
local function VoteRoute(section, vote)
    if vote.individual then
        return nil, nil
    end
    local option = section.options[vote.result.optionIndex]
    return option, PartyScoped((option ~= nil and option.free or {}).effects)
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
        local option, effects = VoteRoute(section, vote)
        return NextAfter(beat, m, section, option, effects, partySize), true
    end
    --everyone has rolled a group test: it leaves by its own exit.
    if section ~= nil and g.group ~= nil and g.group.sectionId == section.id and g.group.result ~= nil then
        return NextAfter(beat, m, section, nil, {}, partySize), true
    end
    return nil, false
end

--Does a fight come straight after the narrative at beatIndex? Then its end
--screen says "Draw Steel!" and waits for a click (HoldDone).
function EncounterGauntlet.FightFollows(script, beatIndex)
    if script == nil or script.parse == nil or beatIndex == nil then
        return false
    end
    local nextBeat = script.parse.beats[beatIndex + 1]
    return nextBeat ~= nil and nextBeat.kind == "encounter"
end

--For the stage: does this section's implicit Proceed end the narrative?
--Then its button is the narrative's last click.
function EncounterGauntlet.ProceedEnds(beat, m, section)
    if section == nil or not section.implicitOption then
        return false
    end
    return NextAfter(beat, m, section, section.options[1], {}, #EncounterMontage.Heroes()) == nil
end

--Host, from the montage's tick while the beat is done: true holds the end
--screen until someone presses its "Draw Steel!" (a "drawSteel" request).
--Only when a fight follows; any other end moves on by itself.
function EncounterGauntlet.HoldDone(doc, script, beatIndex)
    local m = doc.data.montage
    if type(m) ~= "table" or m.doneAck or not EncounterGauntlet.FightFollows(script, beatIndex) then
        return false
    end
    local clicked = {}
    for userid, req in pairs(m.requests or {}) do
        if type(req) == "table" and (tonumber(req.seq) or 0) > (tonumber((m.handled or {})[userid]) or 0) then
            clicked[#clicked + 1] = { userid = userid, seq = req.seq, kind = req.kind }
        end
    end
    if #clicked == 0 then
        return true
    end
    local go = false
    doc:BeginChange()
    m = doc.data.montage
    m.handled = m.handled or {}
    for _, c in ipairs(clicked) do
        --every request is used up here; only a "drawSteel" moves on.
        m.handled[c.userid] = c.seq
        if c.kind == "drawSteel" then
            go = true
        end
    end
    if go then
        m.doneAck = true
        m.doneAt = Now()
        printf("EotW narrative: Draw Steel! pressed; the fight begins")
    end
    doc:CompleteChange("Narrative: Draw Steel!", { undoable = false })
    return not go
end

--The backdrop while the party is at a section: its own [[scene]], else the
--beat's (a custom event's section uses its point's, then the beat's).
function EncounterGauntlet.SceneImage(script, beat)
    local m = EncounterMontage.GetState()
    local section = nil
    if m ~= nil and beat ~= nil and m.beatIndex ~= nil and script ~= nil and script.parse ~= nil
        and script.parse.beats[m.beatIndex] == beat then
        section = EncounterGauntlet.CurrentSection(beat, m)
        if section == nil and m.phase == "done" then
            section = EncounterGauntlet.LastSection(beat, m)
        end
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

--How many effects landed in a settled choice (all groups together).
local function VoteApplied(result)
    local n = #((result or {}).applied or {})
    for _, group in ipairs((result or {}).groups or {}) do
        n = n + #(group.applied or {})
    end
    return n
end

--An individual section: every hero has chosen. Each option is applied once,
--for the heroes who took it, so a party-wide clause on it does not land
--once per hero.
local function ResolveIndividual(m, doc, section, heroes)
    local g = m.gauntlet
    local order, byOption = {}, {}
    for _, hero in ipairs(heroes) do
        local choice = (g.vote.choices or {})[hero.charid]
        local index = choice ~= nil and tonumber(choice.optionIndex) or nil
        local option = index ~= nil and section.options[index] or nil
        if index ~= nil and option ~= nil then
            if byOption[index] == nil then
                byOption[index] = { optionIndex = index, optionName = option.name, heroes = {}, heroNames = {} }
                order[#order + 1] = index
            end
            local group = byOption[index]
            group.heroes[#group.heroes + 1] = hero
            group.heroNames[#group.heroNames + 1] = hero.name
        end
    end
    table.sort(order)
    local groups = {}
    for _, index in ipairs(order) do
        local group = byOption[index]
        local applied, newAllies = EncounterMontage.ApplyEffects((section.options[index].free or {}).effects or {}, {
            heroEntries = group.heroes,
            heroEntry = group.heroes[1],
            userid = group.heroes[1] ~= nil and group.heroes[1].ownerId or nil,
            entryName = section.name,
            entryId = section.id,
            source = T("narrative.effect_source"),
            montage = m,
            doc = doc,
        })
        for _, charid in ipairs(newAllies or {}) do
            EncounterMontage.RecordAlly(doc, group.heroes[1].charid, charid)
        end
        groups[#groups + 1] = { optionIndex = index, optionName = group.optionName, heroNames = group.heroNames, applied = applied }
    end
    g.vote.result = { groups = groups, applied = {}, at = Now() }
    m.log = m.log or {}
    m.log[#m.log + 1] = {
        round = 1,
        choice = true,
        individual = true,
        entryId = section.id,
        entryName = section.name,
        groups = groups,
    }
    --analytics: how many heroes took each option ("2,1,0" by option order).
    local counts = {}
    for i = 1, #section.options do
        counts[i] = "0"
    end
    for _, group in ipairs(groups) do
        counts[group.optionIndex] = tostring(#group.heroNames)
    end
    EotwAnalytics.Track("eotw_narrative_choice", {
        section = section.name,
        mode = "individual",
        options = #section.options,
        landed = VoteApplied(g.vote.result),
        optionCounts = table.concat(counts, ","),
    })
    printf("EotW narrative: every hero has chosen at '%s'", tostring(section.name))
end

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
        source = T("narrative.effect_source"),
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
    --the narrative's own event, as it has always been sent.
    EotwAnalytics.Track("eotw_narrative_choice", {
        section = section.name,
        mode = "together",
        options = #section.options,
        landed = #applied,
        option = option.name,
        optionIndex = optionIndex,
        decidedBy = decidedBy,
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
        local linger = cond(VoteApplied(vote.result) > 0, RESULT_LINGER_SECONDS, CHOICE_LINGER_QUIET)
        if Now() - (tonumber(vote.result.at) or 0) >= linger then
            local option, effects = VoteRoute(section, vote)
            MoveOn(m, doc, beat, heroes, section, option, effects)
            --the last section's Proceed was already the party's "Draw
            --Steel!" click (the stage labels it so): the end screen does
            --not wait for a second one.
            if m.phase == "done" and section.implicitOption then
                m.doneAck = true
            end
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
    --a section with no options (the implicit Proceed) is not a choice: any
    --one player's click moves the whole party on.
    if section.implicitOption then
        if next(vote.choices or {}) ~= nil then
            ResolveVote(m, doc, section, heroes, 1, nil)
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
    if vote.individual then
        ResolveIndividual(m, doc, section, heroes)
        return
    end
    if split and BeginDecision(m, section, heroes) then
        return
    end
    ResolveVote(m, doc, section, heroes, first or 1, nil)
end

--- group tests: "Everyone rolls:" (host) -------------------------------------------
--Every hero makes the section's one test at the same time, each on their
--own player's screen. Each result applies to that hero alone ("you lose 2
--recoveries" is the roller's), with their own knack version, riders and
--Weary. When every hero has rolled the party leaves by the section's exit.

--The version of a group test a hero rolls (their first knack, else the test).
local function GroupVersion(section, charid)
    local option = section.options[1]
    if option == nil then
        return nil, nil, nil
    end
    local knackIndex = EncounterMontage.KnackIndex(charid, option)
    return EncounterScript.OptionVersion(option, knackIndex), option, knackIndex
end

--Host: the dice come out for every hero present.
local function OpenGroup(m, section, heroes)
    local option = section.options[1]
    local group = { sectionId = section.id, startedAt = Now(), order = {}, heroes = {} }
    for _, hero in ipairs(heroes) do
        m.seq = (m.seq or 0) + 1
        --a hero the whole party shares is rolled by the host's player.
        local userid = hero.ownerId
        if userid == nil or userid == "" or userid == "PARTY" then
            userid = dmhub.loginUserid
        end
        local knackIndex = EncounterMontage.KnackIndex(hero.charid, option)
        group.order[#group.order + 1] = hero.charid
        group.heroes[hero.charid] = {
            heroName = hero.name,
            userid = userid,
            rollSeq = m.seq,
            status = "rolling",
            startedAt = Now(),
            knackReason = EncounterMontage.KnackReason(hero.charid, option, knackIndex),
        }
    end
    m.gauntlet.group = group
    printf("EotW narrative: everyone rolls at '%s' (%d heroes)", tostring(section.name), #group.order)
end

--Host: one hero's group roll has landed (or the host rolled it for them).
local function LandGroupRoll(m, doc, section, heroes, charid, tier, total, natural, auto)
    local g = m.gauntlet
    local rec = g.group.heroes[charid]
    local version, option = GroupVersion(section, charid)
    if rec == nil or version == nil or version.roll == nil or option == nil then
        return
    end
    local tierIndex = M().TierIndexForRoll(version.roll, tier, natural)
    local hero = M().HeroByCharid(heroes, charid)
    local applied = {}
    if hero ~= nil then
        local newAllies
        applied, newAllies = EncounterMontage.ApplyEffects(EncounterMontage.VersionEffects(version, tierIndex), {
            heroEntry = hero,
            userid = rec.userid,
            entryName = section.name,
            entryId = section.id,
            entry = section,
            montage = m,
            doc = doc,
        })
        for _, allyid in ipairs(newAllies or {}) do
            EncounterMontage.RecordAlly(doc, charid, allyid)
        end
    end
    CountRoll(m, charid)
    rec.status = "done"
    rec.tier = tierIndex
    rec.total = total
    rec.auto = auto or nil
    rec.tierText = EncounterScript.SubstitutePC(EncounterScript.VisibleText(version.roll.tiers[tierIndex] or ""), rec.heroName, EncounterMontage.HeroPronouns(charid))
    rec.applied = applied
    m.log = m.log or {}
    m.log[#m.log + 1] = {
        round = 1,
        group = true,
        heroid = charid,
        heroName = rec.heroName,
        entryId = section.id,
        entryName = section.name,
        optionName = option.name,
        tier = tierIndex,
        total = total,
        tierText = rec.tierText,
        applied = applied,
        knack = rec.knackReason,
    }
    EotwAnalytics.Track("eotw_montage_test", {
        beat = doc.data.beat,
        round = 1,
        entry = section.name,
        entryKind = "group",
        option = option.name,
        attr = version.roll.attr,
        rolled = true,
        tier = tierIndex,
        total = total,
        natural = natural,
        knack = rec.knackReason ~= nil,
        owner = rec.userid,
        effects = #applied,
        auto = auto or nil,
    })
    printf("EotW narrative: %s rolled tier %d at '%s'%s", tostring(rec.heroName), tierIndex, tostring(section.name),
        cond(auto, " (rolled by the host)", ""))
end

--Host: roll a group test for a hero whose player has not (2d10 + the
--best listed characteristic; no edges or banes).
local function AutoRollFor(m, doc, section, heroes, charid)
    local version = GroupVersion(section, charid)
    local modifier = 0
    pcall(function()
        local attrid = EncounterMontage.TestCharacteristic(charid, version)
        local tok = dmhub.GetCharacterById(charid)
        local attr = attrid ~= nil and tok ~= nil and tok.properties:GetAttribute(attrid) or nil
        if attr ~= nil then
            modifier = attr:Modifier()
        end
    end)
    local natural = math.random(1, 10) + math.random(1, 10)
    local total = natural + modifier
    local tier = 3
    if total <= 11 then
        tier = 1
    elseif total <= 16 then
        tier = 2
    end
    LandGroupRoll(m, doc, section, heroes, charid, tier, total, natural, true)
end

--Host, every tick while a group test is on the board.
local function TickGroup(m, doc, beat, section, heroes)
    local g = m.gauntlet
    local group = g.group
    if group == nil or group.sectionId ~= section.id then
        OpenGroup(m, section, heroes)
        return
    end
    if group.result ~= nil then
        local linger = cond((group.result.applied or 0) > 0, RESULT_LINGER_SECONDS, RESULT_LINGER_QUIET)
        if Now() - (tonumber(group.result.at) or 0) >= linger then
            MoveOn(m, doc, beat, heroes, section, nil, {})
        end
        return
    end
    local waiting = false
    for _, hero in ipairs(heroes) do
        --a hero who joined after the dice came out sits this one out.
        local rec = group.heroes[hero.charid]
        if rec ~= nil and rec.status ~= "done" then
            if Now() - (tonumber(rec.startedAt) or Now()) >= GROUP_ROLL_SECONDS then
                printf("EotW narrative: %s never rolled at '%s'; the host rolls for them", tostring(rec.heroName), tostring(section.name))
                AutoRollFor(m, doc, section, heroes, hero.charid)
            else
                waiting = true
            end
        end
    end
    if waiting then
        return
    end
    local applied = 0
    for _, rec in pairs(group.heroes) do
        applied = applied + #(rec.applied or {})
    end
    group.result = { at = Now(), applied = applied }
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
        if t.interrupted then
            linger = RESULT_LINGER_INTERRUPTED
        end
        --a test that really landed ends the emote held on its hero (an
        --interrupted roll is not a test that landed), unless this test's own
        --outcome lines gave it: that one is the hero's latest.
        local held = m.gauntlet.heroEmote
        if not t.interrupted and type(held) == "table" and held.heroid == t.heroid
            and not (held.seq == t.seq and held.part == "outcome") then
            m.gauntlet.heroEmote = nil
        end
        if Now() - (tonumber(t.resolvedAt) or 0) >= linger then
            local entry = EncounterMontage.TurnEntry(beat, t)
            local version = EncounterMontage.TurnOption(entry, t)
            local base = EncounterMontage.TurnBaseOption(entry, t)
            MoveOn(m, doc, beat, heroes, entry or section, base, EncounterMontage.VersionEffects(version, t.tier))
        end
        return
    end

    if m.turn == nil and (section.kind == "choice" or section.kind == "individual") and m.gauntlet.vote ~= nil then
        TickVote(m, doc, beat, section, heroes)
    end
    --everyone rolls (once any arrival scene has been read).
    if m.turn == nil and section.kind == "group" then
        TickGroup(m, doc, beat, section, heroes)
    end
    --a spotlight section with one way through: its hero steps up at once.
    if m.turn == nil and section.kind == "challenge" then
        EncounterGauntlet.SpotlightAutoClaim(m, doc, beat, section, heroes)
    end
end

--Host: "(Spotlight)": when the spotlight hero can take exactly one of the
--section's options, it is claimed for them (they are forced to take it).
--With a choice of options, the claim is theirs to make.
function EncounterGauntlet.SpotlightAutoClaim(m, doc, beat, section, heroes)
    local s = m.gauntlet.spotlight
    if s == nil or s.sectionId ~= section.id or s.autoTried then
        return
    end
    s.autoTried = true
    local I = M()
    local hero = I.HeroByCharid(heroes, s.heroid)
    if hero == nil then
        m.gauntlet.spotlight = nil
        return
    end
    local only = nil
    for i, option in ipairs(section.options) do
        local verdict = EncounterMontage.RiderVerdict(hero.charid, option, nil)
        if verdict == nil or verdict.allowed then
            if only ~= nil then
                return
            end
            only = i
        end
    end
    if only == nil then
        --nothing this hero can take: the section is open to everyone.
        m.gauntlet.spotlight = nil
        return
    end
    local userid = hero.ownerId
    if userid == nil or userid == "" or userid == "PARTY" then
        userid = s.userid
    end
    m.seq = (m.seq or 0) + 1
    m.turn = {
        seq = m.seq,
        gauntlet = true,
        forced = true,
        userid = userid,
        heroid = hero.charid,
        heroName = hero.name,
        entryId = section.id,
        status = "choosing",
        startedAt = Now(),
    }
    local line = I.ChooseOption(m, doc, m.turn, beat, only, heroes, userid)
    if m.turn ~= nil and m.turn.status == "choosing" then
        m.turn = nil
    else
        m.gauntlet.lastClaim = { heroid = hero.charid, userid = userid, heroName = hero.name }
    end
    printf("EotW narrative: %s is in the spotlight at '%s': %s", tostring(hero.name), tostring(section.name), tostring(line))
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
            --an interrupted roll never happened, so it is no Weary.
            local option = EncounterMontage.TurnOption(EncounterMontage.TurnEntry(beat, t), t)
            if option == nil or option.roll == nil or not option.roll.interrupted then
                CountRoll(m, t.heroid)
            end
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
        assistCancel = true, proceedTest = true, bless = true, vote = true, unvote = true,
        groupRolled = true, groupCancel = true }
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
        if section.kind ~= "challenge" then
            return true, "ignored claim: this section is decided by choosing, not taken on"
        end
        local hero = I.HeroByCharid(heroes, req.heroid)
        if hero == nil or not I.UserControlsHero(userid, hero) then
            return true, "ignored claim: not your hero"
        end
        local spot = g.spotlight
        if spot ~= nil and spot.sectionId == section.id and spot.heroid ~= hero.charid then
            return true, string.format("ignored claim: %s is in the spotlight here", tostring(spot.heroName))
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
        else
            --a later "(Spotlight)" section belongs to this hero.
            g.lastClaim = { heroid = hero.charid, userid = userid, heroName = hero.name }
        end
        return true, line
    end

    if kind == "groupRolled" or kind == "groupCancel" then
        local group = g.group
        local rec = group ~= nil and group.heroes[req.heroid or ""] or nil
        if section.kind ~= "group" or group == nil or group.sectionId ~= section.id or rec == nil then
            return true, string.format("ignored %s: no group test", kind)
        end
        if rec.status ~= "rolling" or rec.rollSeq ~= req.rollSeq then
            return true, string.format("ignored %s: stale", kind)
        end
        local hero = I.HeroByCharid(heroes, req.heroid)
        if rec.userid ~= userid and (hero == nil or not I.UserControlsHero(userid, hero)) then
            return true, string.format("ignored %s: not your hero", kind)
        end
        if kind == "groupCancel" then
            --the roll dialog closed unthrown; it comes back (the test is not
            --optional).
            return true, string.format("%s put the dice down", tostring(rec.heroName))
        end
        LandGroupRoll(m, doc, section, heroes, req.heroid, req.tier, req.total, req.natural, false)
        return true, string.format("%s rolled at %s", tostring(rec.heroName), section.name)
    end

    if kind == "vote" or kind == "unvote" then
        local vote = g.vote
        if (section.kind ~= "choice" and section.kind ~= "individual") or vote == nil or t ~= nil then
            return true, "ignored vote: not voting"
        end
        if vote.decision ~= nil or vote.result ~= nil then
            return true, "ignored vote: the vote is settled"
        end
        --a vote is the player's (one voice however many heroes they run);
        --an individual choice is a hero's, so it names the hero.
        local key = nil
        if vote.individual then
            local hero = I.HeroByCharid(heroes, req.heroid)
            if hero == nil or not I.UserControlsHero(userid, hero) then
                return true, "ignored choice: not your hero"
            end
            key = hero.charid
        else
            key = EncounterNarrative.VoterKeyForUser(userid, heroes)
        end
        --anyone may press an implicit Proceed, the Director included.
        if key == nil and section.implicitOption then
            key = userid
        end
        if key == nil then
            return true, "ignored vote: controls no hero"
        end
        vote.choices = vote.choices or {}
        if kind == "unvote" then
            vote.choices[key] = nil
            return true, string.format("%s took their choice back", tostring(key))
        end
        local index = tonumber(req.optionIndex)
        if index == nil or section.options[index] == nil then
            return true, "ignored vote: no such option"
        end
        vote.choices[key] = { optionIndex = index, userid = userid, heroid = req.heroid, at = Now() }
        return true, string.format("%s chose '%s'", tostring(key), section.options[index].name)
    end

    --everything below acts on the claimed turn.
    if t == nil or not t.gauntlet or t.arrival then
        return true, string.format("ignored %s: no option is being taken", tostring(kind))
    end

    if kind == "unclaim" then
        if t.userid ~= userid then
            return true, "ignored unclaim: not your claim"
        end
        if t.forced then
            return true, "ignored unclaim: the hero in the spotlight cannot step back"
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
    --an interrupted test is a fake: nobody gets the chance to help.
    if #EncounterMontage.Heroes() <= 1 or (option ~= nil and option.roll ~= nil and option.roll.interrupted) then
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

--the group-test roll this client has out (one at a time: a player with two
--heroes rolls them one after the other), and when a closed one may come back.
local m_groupRollSeq = nil
local m_groupRetryAt = {}
--a group roll dialog closed without throwing reopens after this long.
local GROUP_RETRY_SECONDS = 2

--Client (EncounterMontage.ClientTick, while no turn is out): roll this
--user's heroes in an "Everyone rolls:" section.
function EncounterGauntlet.GroupClientTick(m)
    local group = m.gauntlet ~= nil and m.gauntlet.group or nil
    if group == nil or group.result ~= nil then
        m_groupRollSeq = nil
        return
    end
    --the roll out is still wanted: wait for it to land.
    if m_groupRollSeq ~= nil then
        for _, rec in pairs(group.heroes) do
            if rec.rollSeq == m_groupRollSeq and rec.status == "rolling" then
                return
            end
        end
        m_groupRollSeq = nil
    end
    local beat = EncounterMontage.CurrentBeat()
    local section = beat ~= nil and EncounterGauntlet.CurrentSection(beat, m) or nil
    if section == nil or section.kind ~= "group" or section.id ~= group.sectionId then
        return
    end
    for _, charid in ipairs(group.order or {}) do
        local rec = group.heroes[charid]
        if rec ~= nil and rec.status == "rolling" and rec.userid == dmhub.loginUserid
            and dmhub.Time() >= (m_groupRetryAt[rec.rollSeq] or 0) then
            local token = dmhub.GetCharacterById(charid)
            local version, option = GroupVersion(section, charid)
            if token ~= nil and token.valid and version ~= nil and version.roll ~= nil and option ~= nil then
                m_groupRollSeq = rec.rollSeq
                EncounterGauntlet.LaunchGroupRoll(rec, charid, token, option, version)
                return
            end
        end
    end
end

--Show one hero's group-test roll: the montage's test roll (best listed
--characteristic, Skilled, features, riders) plus their Weary.
function EncounterGauntlet.LaunchGroupRoll(rec, charid, token, option, version)
    local I = M()
    local built = EncounterMontage.BuildTestRoll(token, version.roll.attr, version.roll.name,
        EncounterMontage.RiderVerdict(charid, option, version))
    EncounterGauntlet.AppendRollModifiers(built.modifiers, nil, charid, false)
    local rollSeq = rec.rollSeq
    local function StillWanted()
        local m = EncounterMontage.GetState()
        local group = m ~= nil and m.gauntlet ~= nil and m.gauntlet.group or nil
        local now = group ~= nil and group.heroes[charid] or nil
        return now ~= nil and now.status == "rolling" and now.rollSeq == rollSeq
    end
    I.ShowMontageRoll {
        creature = token.properties,
        heroToken = token,
        title = string.format("%s: %s", rec.heroName or token.name or "?", built.title),
        rollType = built.rollType,
        roll = built.roll,
        modifiers = built.modifiers,
        tiers = EncounterMontage.TeaserTiers(version.roll, rec.heroName, EncounterMontage.HeroPronouns(charid)),
        secretCritical = true,
        rollSeq = rollSeq,
        stillWanted = StillWanted,
        completeKind = "groupRolled",
        cancelKind = "groupCancel",
        extra = { heroid = charid },
        onNotShown = function()
            m_groupRollSeq = nil
        end,
        send = function(kind, args)
            if kind == "groupCancel" then
                --closed unthrown: it comes back shortly.
                m_groupRetryAt[rollSeq] = dmhub.Time() + GROUP_RETRY_SECONDS
                m_groupRollSeq = nil
            end
            args = args or {}
            args.heroid = charid
            return EncounterMontage.SendRequest(kind, args)
        end,
    }
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
            "# Narrative",
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

--Host: settle the choice on the board on the choices already in, without
--waiting for a missing player ("/eotwnarrative force"). A vote takes the
--first option anyone chose (option 1 if nobody has); an individual section
--applies what the heroes who chose took.
function EncounterGauntlet.ForceResolve()
    local beat = EncounterMontage.CurrentBeat()
    local doc = EncounterMontage.GetDoc()
    local m = doc.data.montage
    local g = type(m) == "table" and m.gauntlet or nil
    if beat ~= nil and g ~= nil and g.group ~= nil and g.group.result == nil and m.turn == nil then
        --"Everyone rolls:": the host rolls for every hero still to roll.
        local section = EncounterGauntlet.CurrentSection(beat, m)
        if section == nil or section.kind ~= "group" then
            return false, "no section"
        end
        local heroes = EncounterMontage.Heroes()
        doc:BeginChange()
        m = doc.data.montage
        for _, charid in ipairs(m.gauntlet.group.order or {}) do
            local rec = m.gauntlet.group.heroes[charid]
            if rec ~= nil and rec.status == "rolling" then
                AutoRollFor(m, doc, section, heroes, charid)
            end
        end
        doc:CompleteChange("Narrative: forced group rolls", { undoable = false })
        return true
    end
    if beat == nil or g == nil or g.vote == nil or g.vote.result ~= nil or m.turn ~= nil then
        return false, "no choice is waiting"
    end
    local section = EncounterGauntlet.CurrentSection(beat, m)
    if section == nil then
        return false, "no section"
    end
    local heroes = EncounterMontage.Heroes()
    doc:BeginChange()
    m = doc.data.montage
    g = m.gauntlet
    if g.vote.individual then
        ResolveIndividual(m, doc, section, heroes)
    else
        local chosen = nil
        for _, choice in pairs(g.vote.choices or {}) do
            chosen = chosen or tonumber(choice.optionIndex)
        end
        g.vote.decision = nil
        ResolveVote(m, doc, section, heroes, chosen or 1, nil)
    end
    doc:CompleteChange("Narrative: forced", { undoable = false })
    return true
end

--"/eotwgauntlet state": where the party is, the fatigue counts and the turn.
function EncounterGauntlet.PrintState()
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
        doc = "Usage: /eotwgauntlet state | json\nstate prints the section on the board, the path so far, each hero's roll count (fatigue) and the turn; json prints the raw state. Run the map's first narrative here with /eotwnarrative start.",
        command = function(str)
            local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
            if arg == "json" then
                print(json(EncounterGauntlet.GetState()))
            else
                EncounterGauntlet.PrintState()
            end
        end,
    }
end)
