--Encounter of the Week: Tactical Preparation.
--
--The screen that comes up at the outset of the encounter, once a script has
--unlocked the Intelligence feature ("Unlock: Intelligence" in a narrative
--beat -- see EncounterScript.FEATURES). The party spends the Intelligence
--they earned during the montage on what they know going into the fight:
--
--  * Surprise      -- five levels, from "You are surprised" to "The enemy is
--                     surprised". It OPENS on whatever the montage decided
--                     (EncounterMontage.GetInitiativeOutcome), so a party
--                     that got the jump starts higher up the bar.
--  * Traps         -- 0: nothing known. 1: two of the placed traps, drawn
--                     at random, are marked (EncounterZones.BankPartialReveal).
--                     2: every trap on the map is marked (the montage clause
--                     "Reveal Traps", banked the same way).
--  * Enemy Stamina -- 0: no bars at all. 1: bars with no numbers. 2: bars
--                     with the exact Stamina. Driven by the game setting
--                     "enemystambardisplay", which the EotW host re-asserts
--                     every tick (EncounterOfTheWeek.lua EnforceStrictRules).
--
--Each notch costs 1 Intelligence. Each player spends the Intelligence their
--own heroes earned (EncounterMontage.GetHeroIntelligence), plus any shared
--part no hero holds; nobody sees the levels above the one they are on --
--only what they know now. Once a player's own Intelligence is spent (or
--nothing is left to raise) they press Proceed, and the encounter begins
--when every player has.
--
--Design: EncounterOfTheWeek.md, "Tactical Preparation".
--
--Authority model is the montage's and the narrative's: the HOST is the single
--writer of prep.* state, from the map script's host tick (HostTick, called by
--RunScriptBeat before the traps are placed and the monsters spawned). Players
--only stamp prep.requests[userid] (SendRequest) and the host validates and
--applies them in order.
--
--The shared document is the montage's ("eotwscript"), under its own key:
--  data.prep = {
--    beatIndex, phase = "spending"|"resolved"|"done",
--    bars = { { id, level }, ... },       -- in display order
--    start = { [barId] = level },         -- what it opened on
--    spent = { { bar, userid, name, level, at }, ... },
--    ready = { [userid] = { name, at } },
--    applied = { "..." },                 -- what the resolution really did
--    requests = { [userid] = { seq, kind, ... } }, handled = { [userid] = seq },
--    startedAt, resolvedAt, doneAt, seq,
--  }
--
--The pool itself is data.intelligence (the party total) and
--data.intelligenceByHero (each hero's share), at the top level of the same
--document (EncounterMontage.GetIntelligence), because it spans every beat.

local mod = dmhub.GetModLoading()

local T = UIText.T

EncounterPrep = rawget(_G, "EncounterPrep") or {}

local DOC_ID = "eotwscript"

--what one notch costs.
local SPEND_COST = 1
--how long the resolved screen holds before the encounter takes over. The
--party has just read what their Intelligence bought; the traps go down and
--the monsters spawn behind it either way.
local RESOLVED_LINGER_SECONDS = 4

EncounterPrep.TITLE = T("prep.title")
EncounterPrep.INSTRUCTIONS = T("prep.instructions")

--- the bars ------------------------------------------------------------------

--The surprise bar's five rungs, worst to best. Index here is level + 1.
local SURPRISE_LEVELS = {
    T("prep.surprise.level0"),
    T("prep.surprise.level1"),
    T("prep.surprise.level2"),
    T("prep.surprise.level3"),
    T("prep.surprise.level4"),
}

local STAMINA_LEVELS = {
    T("prep.stamina.level0"),
    T("prep.stamina.level1"),
    T("prep.stamina.level2"),
}

--What the enemy stamina bar's level means to the game setting that draws
--them: no bar, a bar with no number, or a bar with the exact Stamina.
local STAMINA_SETTING = { [0] = "none", [1] = "bar", [2] = "val" }

--How many of the placed traps level 1 of the traps bar marks.
local PARTIAL_TRAP_REVEALS = 2

--Every "place N objects in <zone> zones" instruction of the encounter beat.
--These are what the traps bar is about: with none, the bar is not offered.
function EncounterPrep.TrapInstructions(beat)
    local result = {}
    for _, ins in ipairs((beat and beat.setup) or {}) do
        if ins.kind == "placeobjects" and ins.zone ~= nil then
            result[#result + 1] = ins
        end
    end
    return result
end

--Level 1 of the traps bar: for their first point the party learns where a
--few of the traps are (PARTIAL_TRAP_REVEALS of them, marked when the zones
--go down), but not how many there are in all.
function EncounterPrep.TrapsDescription(beat)
    if #EncounterPrep.TrapInstructions(beat) == 0 then
        return T("prep.traps.level1_none")
    end
    return T("prep.traps.level1")
end

--The bar's display: its title and the text of every level, so the stage
--never has to know what a level means. The level texts past the one the
--party is on are still here -- the STAGE is what withholds them, because
--the host has to be able to say what a spend bought.
function EncounterPrep.BarInfo(beat, barId)
    if barId == "surprise" then
        return { id = barId, title = T("prep.surprise.title"), levels = SURPRISE_LEVELS }
    end
    if barId == "traps" then
        return { id = barId, title = T("prep.traps.title"), levels = {
            T("prep.traps.level0"),
            EncounterPrep.TrapsDescription(beat),
            T("prep.traps.level2"),
        } }
    end
    if barId == "stamina" then
        return { id = barId, title = T("prep.stamina.title"), levels = STAMINA_LEVELS }
    end
    return { id = tostring(barId), title = tostring(barId), levels = { "" } }
end

function EncounterPrep.MaxLevel(beat, barId)
    return #EncounterPrep.BarInfo(beat, barId).levels - 1
end

--- the document ---------------------------------------------------------------

function EncounterPrep.GetDoc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

--The live preparation state, or nil when no preparation is running.
function EncounterPrep.GetState()
    local m = nil
    pcall(function() m = mod:GetDocumentSnapshot(DOC_ID).data.prep end)
    if type(m) ~= "table" then
        return nil
    end
    return m
end

--Is the Tactical Preparation screen what should be on the stage right now?
--(The mounted script stage asks this when the script reaches the encounter
--beat; everything else about that beat happens behind the stage.)
function EncounterPrep.IsLive()
    local m = EncounterPrep.GetState()
    return m ~= nil and m.phase ~= "done"
end

--Does this script want a preparation screen at all? Only a week that
--unlocked Intelligence gets one.
function EncounterPrep.Required()
    return EncounterMontage.FeatureUnlocked("intelligence")
end

function EncounterPrep.Level(m, barId)
    for _, bar in ipairs((m or {}).bars or {}) do
        if bar.id == barId then
            return tonumber(bar.level) or 0
        end
    end
    return nil
end

--What the enemy stamina bars should be showing: the level the party bought,
--or the game mode's own default when the feature is not in play. Read by
--the host's EnforceStrictRules, so it is the one authority on the setting.
function EncounterPrep.EnemyStaminaDisplay()
    if not EncounterPrep.Required() then
        --no Intelligence in this week: bars with no numbers, as EotW has
        --always shown them.
        return "bar"
    end
    local m = EncounterPrep.GetState()
    local level = EncounterPrep.Level(m, "stamina") or 0
    return STAMINA_SETTING[level] or "none"
end

--- the opening levels ---------------------------------------------------------

--Where the surprise bar starts: what the montage decided. A party the
--montage surprised opens at the bottom and has to buy its way out; a party
--that surprised the enemy is already at the top.
function EncounterPrep.StartingSurpriseLevel()
    local outcome = nil
    local partySurprised, enemySurprised = nil, nil
    local immune = false
    pcall(function() outcome = EncounterMontage.GetInitiativeOutcome() end)
    pcall(function() partySurprised, enemySurprised = EncounterMontage.GetSurprisedSides() end)
    pcall(function() immune = EncounterMontage.HasSurpriseImmunity() end)

    --the condition outranks the outcome, exactly as it does at combat start.
    if partySurprised ~= nil and not immune then
        return 0
    end
    if enemySurprised ~= nil then
        return 4
    end
    if outcome == "surprised" or outcome == "lose" then
        return 1
    end
    if outcome == "win" then
        return 3
    end
    if outcome == "surprise" then
        return 4
    end
    return 2
end

--Where the traps bar starts: at the top when the montage already earned
--"Reveal Traps" for every zone the encounter uses, otherwise at nothing.
--(There is no middle ground to inherit: level 1 is a fact the party is
--told, and the montage has no clause that tells them.)
local function StartingTrapsLevel(doc, beat)
    local instructions = EncounterPrep.TrapInstructions(beat)
    if #instructions == 0 then
        return 0
    end
    local banked = doc.data.revealZones or {}
    local revealed = doc.data.zonesRevealed or {}
    --a partial reveal (this bar's own level 1) only marks a few of the
    --traps, so it does not count as the zone being revealed.
    local function Full(entry)
        return entry ~= nil and entry.partial == nil
    end
    for _, ins in ipairs(instructions) do
        if not Full(banked[ins.zone]) and not Full(revealed[ins.zone]) then
            return 0
        end
    end
    return 2
end

--- voters ---------------------------------------------------------------------

--Everyone who has to press Proceed: one voice per PLAYER, however many
--heroes they run, exactly like an agreed-upon narrative section. (Heroes
--owned by the party collapse into one pseudo-voter, so the authoring game
--has a single Proceed to press.)
function EncounterPrep.Voters(heroes)
    local narrative = rawget(_G, "EncounterNarrative")
    if narrative ~= nil and narrative.Voters ~= nil then
        return narrative.Voters(nil, heroes)
    end
    return {}
end

function EncounterPrep.VoterKeyForUser(userid, heroes)
    local narrative = rawget(_G, "EncounterNarrative")
    if narrative ~= nil and narrative.VoterKeyForUser ~= nil then
        return narrative.VoterKeyForUser(userid, heroes)
    end
    return nil
end

--The heroes a voter (a player's userid, or "PARTY") runs: whose
--Intelligence that player spends.
function EncounterPrep.VoterHeroids(key, heroes)
    for _, voter in ipairs(EncounterPrep.Voters(heroes)) do
        if voter.key == key then
            return voter.heroids
        end
    end
    return {}
end

--What the local player may spend right now: their own heroes' Intelligence
--plus the shared part. 0 for an onlooker.
function EncounterPrep.LocalSpendable()
    local key = EncounterPrep.VoterKeyForUser(dmhub.loginUserid, nil)
    if key == nil then
        return 0
    end
    return EncounterMontage.SpendableIntelligence(EncounterPrep.VoterHeroids(key, nil))
end

--Who is still to press Proceed, as display names. skipKey drops one voter
--from the list -- the stage passes the local player's own key, because a
--screen that says "waiting for you" next to your own Proceed button reads
--like a fault rather than a prompt.
function EncounterPrep.PendingVoters(m, heroes, skipKey)
    local pending = {}
    for _, voter in ipairs(EncounterPrep.Voters(heroes)) do
        if voter.key ~= skipKey and ((m or {}).ready or {})[voter.key] == nil then
            pending[#pending + 1] = voter.name
        end
    end
    return pending
end

--- what the local client may do ------------------------------------------------

--Can this player buy anything? (Both gates: a point of their own to spend,
--and a bar that can still take one.)
--`pool` is what the player may spend; nil means the local player
--(LocalSpendable). The host passes what the OPEN document says for the
--player whose request it is handling, so a Proceed handled in the same
--tick as the spend that emptied it is judged against the new number.
function EncounterPrep.CanSpend(m, beat, pool)
    if m == nil or m.phase ~= "spending" then
        return false
    end
    if (pool or EncounterPrep.LocalSpendable()) < SPEND_COST then
        return false
    end
    for _, bar in ipairs(m.bars or {}) do
        if (tonumber(bar.level) or 0) < EncounterPrep.MaxLevel(beat, bar.id) then
            return true
        end
    end
    return false
end

--A player's Proceed button is offered once their Intelligence is spent --
--either because they have none left or because there is nothing left to
--raise (an Intelligence nobody can spend must not wedge the encounter).
--`pool` as for CanSpend.
function EncounterPrep.CanProceed(m, beat, pool)
    return m ~= nil and m.phase == "spending" and not EncounterPrep.CanSpend(m, beat, pool)
end

--Has the local player already pressed Proceed?
function EncounterPrep.LocalUserReady(m)
    local key = EncounterPrep.VoterKeyForUser(dmhub.loginUserid, nil)
    if key == nil then
        return false
    end
    return ((m or {}).ready or {})[key] ~= nil
end

--Is this client one of the party (rather than an onlooker)?
function EncounterPrep.LocalUserIsVoter()
    return EncounterPrep.VoterKeyForUser(dmhub.loginUserid, nil) ~= nil
end

--- requests (player side) ------------------------------------------------------

--Stamp a request for the host: {seq, kind, ...args}. One slot per user; a
--newer request replaces an unhandled older one.
function EncounterPrep.SendRequest(kind, args)
    local userid = dmhub.loginUserid
    local doc = EncounterPrep.GetDoc()
    if doc.data.prep == nil then
        return false
    end
    doc:BeginChange()
    local m = doc.data.prep
    m.requests = m.requests or {}
    local prev = m.requests[userid]
    local req = { seq = ((prev ~= nil and prev.seq) or 0) + 1, kind = kind, time = dmhub.serverTime }
    for k, v in pairs(args or {}) do
        req[k] = v
    end
    m.requests[userid] = req
    doc:CompleteChange("Preparation request: " .. tostring(kind), { undoable = false })
    return true
end

function EncounterPrep.Spend(barId)
    return EncounterPrep.SendRequest("spend", { bar = barId })
end

function EncounterPrep.Ready()
    return EncounterPrep.SendRequest("ready", {})
end

function EncounterPrep.Unready()
    return EncounterPrep.SendRequest("unready", {})
end

--- resolution ------------------------------------------------------------------

local function DisplayName(userid)
    if userid == "PARTY" then
        return T("prep.party_name")
    end
    local name = userid
    pcall(function() name = dmhub.GetDisplayName(userid) or userid end)
    return name
end

--The montage clauses that carry out a surprise level. The bar only ever
--moves UP, so the job is: take back whatever the montage decided against
--the party ("a fair roll", which clears the Surprised condition and an
--unfavourable outcome and leaves a favourable one alone), then state the
--level they bought.
local function SurpriseEffects(startLevel, level)
    if level <= startLevel then
        return {}
    end
    local effects = {}
    if startLevel <= 1 then
        effects[#effects + 1] = { kind = "fairinitiative", text = "The encounter begins with a fair roll" }
    end
    if level == 1 then
        effects[#effects + 1] = { kind = "initiative", outcome = "lose", text = "You lose the initiative" }
    elseif level == 3 then
        effects[#effects + 1] = { kind = "initiative", outcome = "win", text = "You win the initiative" }
    elseif level == 4 then
        effects[#effects + 1] = { kind = "initiative", outcome = "surprise", text = "You surprise the enemy" }
    end
    return effects
end

--Carry out what the party bought. Host, from the tick, with the document
--open. Everything mechanical goes through EncounterMontage.ApplyEffects, so
--preparation uses the very same machinery a montage outcome does.
local function Resolve(m, doc, beat, heroes)
    local effects = {}
    local applied = {}
    --the surprise clauses are applied on their own because what the party
    --should READ is the rung they bought ("The enemy is surprised."), not
    --the two clauses it took to get there ("... a fair roll ...", "... will
    --surprise the enemy"). Their own lines go to the console instead.
    local surpriseEffects = {}

    local surprise = EncounterPrep.Level(m, "surprise")
    if surprise ~= nil then
        local start = tonumber((m.start or {}).surprise) or surprise
        surpriseEffects = SurpriseEffects(start, surprise)
        if #surpriseEffects > 0 then
            applied[#applied + 1] = SURPRISE_LEVELS[surprise + 1] or ""
        end
    end

    local traps = EncounterPrep.Level(m, "traps")
    if traps ~= nil then
        local start = tonumber((m.start or {}).traps) or traps
        --level 1 alone marks a couple of the traps; level 2 marks them all,
        --so a party that bought both only needs the full reveal.
        if traps == 1 and start < 1 then
            local zones = {}
            for _, ins in ipairs(EncounterPrep.TrapInstructions(beat)) do
                zones[#zones + 1] = ins.zone
            end
            local zoneApi = rawget(_G, "EncounterZones")
            if zoneApi ~= nil and zoneApi.BankPartialReveal ~= nil then
                zoneApi.BankPartialReveal(doc, zones, PARTIAL_TRAP_REVEALS, EncounterPrep.TITLE)
            end
            applied[#applied + 1] = EncounterPrep.TrapsDescription(beat)
        end
        if traps >= 2 and start < 2 then
            local seen = {}
            for _, ins in ipairs(EncounterPrep.TrapInstructions(beat)) do
                if not seen[ins.zone] then
                    seen[ins.zone] = true
                    effects[#effects + 1] = { kind = "revealzones", zone = ins.zone,
                        text = string.format("Reveal %ss", ins.zone) }
                end
            end
        end
    end

    local stamina = EncounterPrep.Level(m, "stamina")
    if stamina ~= nil and stamina > (tonumber((m.start or {}).stamina) or 0) then
        --nothing to apply: the host re-asserts "enemystambardisplay" from
        --the level every tick (EncounterPrep.EnemyStaminaDisplay).
        applied[#applied + 1] = STAMINA_LEVELS[stamina + 1]
    end

    local function Apply(list, keepLines)
        if #list == 0 then
            return
        end
        local ok, lines = pcall(EncounterMontage.ApplyEffects, list, {
            heroEntry = heroes[1],
            userid = heroes[1] ~= nil and heroes[1].ownerId or nil,
            entryName = EncounterPrep.TITLE,
            source = T("prep.effect_source"),
            doc = doc,
        })
        if not ok then
            printf("EotW preparation: applying the party's preparation failed: %s", tostring(lines))
            return
        end
        for _, line in ipairs(lines or {}) do
            if keepLines then
                applied[#applied + 1] = line
            else
                printf("EotW preparation: %s", tostring(line))
            end
        end
    end

    Apply(surpriseEffects, false)
    Apply(effects, true)

    m.applied = applied
    m.phase = "resolved"
    m.resolvedAt = dmhub.serverTime
    m.seq = (tonumber(m.seq) or 0) + 1
    printf("EotW preparation: resolved (%s)", table.concat(applied, "; "))
end

--- host tick -------------------------------------------------------------------

--Validate and apply one player request. Returns a line to log, or nil.
local function HandleRequest(m, doc, userid, req, beat, heroes)
    if m.phase ~= "spending" then
        return nil
    end
    local key = EncounterPrep.VoterKeyForUser(userid, heroes)
    if key == nil then
        return string.format("%s controls no hero and cannot prepare", tostring(userid))
    end
    local name = DisplayName(key)

    if req.kind == "spend" then
        --read the pool off the OPEN document, not a fresh snapshot: several
        --players' spends can be handled in one tick, and the second must see
        --what the first took. A player spends their own heroes' share.
        local heroids = EncounterPrep.VoterHeroids(key, heroes)
        local pool = EncounterMontage.SpendableIntelligence(heroids, doc.data)
        if pool < SPEND_COST then
            return string.format("%s spent Intelligence they do not have", name)
        end
        local bar = nil
        for _, b in ipairs(m.bars or {}) do
            if b.id == req.bar then
                bar = b
            end
        end
        if bar == nil then
            return string.format("%s raised '%s', which is not on the board", name, tostring(req.bar))
        end
        local level = tonumber(bar.level) or 0
        local max = EncounterPrep.MaxLevel(beat, bar.id)
        if level >= max then
            return string.format("%s raised %s, which is already as high as it goes", name, EncounterPrep.BarInfo(beat, bar.id).title)
        end
        bar.level = level + 1
        local heroNames = {}
        for _, hero in ipairs(heroes or EncounterMontage.Heroes()) do
            heroNames[hero.charid] = hero.name
        end
        local _, from = EncounterMontage.SpendIntelligence(doc, heroids, SPEND_COST, heroNames)
        local log = doc.data.intelligenceLog or {}
        log[#log + 1] = {
            value = tonumber(doc.data.intelligence) or 0,
            amount = -SPEND_COST,
            who = name,
            note = T("prep.intelligence_log.spend", { screen = EncounterPrep.TITLE, bar = EncounterPrep.BarInfo(beat, bar.id).title,
                heroes = table.concat(from or {}, ", ") }),
            at = dmhub.serverTime,
        }
        doc.data.intelligenceLog = log
        m.spent = m.spent or {}
        m.spent[#m.spent + 1] = { bar = bar.id, userid = userid, name = name, level = bar.level, at = dmhub.serverTime }
        --a spend can make Proceed possible, and a player who had nothing to
        --wait for should not be left holding a stale Ready from before it.
        m.seq = (tonumber(m.seq) or 0) + 1
        return string.format("%s raised %s to level %d (%d of their Intelligence left, %d in the party)",
            name, EncounterPrep.BarInfo(beat, bar.id).title, bar.level,
            EncounterMontage.SpendableIntelligence(heroids, doc.data), tonumber(doc.data.intelligence) or 0)
    end

    if req.kind == "ready" or req.kind == "unready" then
        m.ready = m.ready or {}
        if req.kind == "unready" then
            m.ready[key] = nil
            m.seq = (tonumber(m.seq) or 0) + 1
            return string.format("%s is no longer ready", name)
        end
        local own = EncounterMontage.SpendableIntelligence(EncounterPrep.VoterHeroids(key, heroes), doc.data)
        if not EncounterPrep.CanProceed(m, beat, own) then
            return string.format("%s is ready, but has Intelligence still to spend", name)
        end
        m.ready[key] = { name = name, at = dmhub.serverTime }
        m.seq = (tonumber(m.seq) or 0) + 1
        return string.format("%s is ready", name)
    end

    return nil
end

--Everyone has pressed Proceed.
local function ReadyComplete(m, heroes)
    local voters = EncounterPrep.Voters(heroes)
    if #voters == 0 then
        return false
    end
    for _, voter in ipairs(voters) do
        if (m.ready or {})[voter.key] == nil then
            return false
        end
    end
    return true
end

--Seed the state and put the stage up. Unlike a montage or a narrative there
--is no "arriving" phase: the host tick only runs once the whole party is in,
--so the first thing anyone sees is a screen they can act on.
function EncounterPrep.Begin(script, beat, beatIndex)
    local doc = EncounterPrep.GetDoc()
    local bars = { { id = "surprise", level = EncounterPrep.StartingSurpriseLevel() } }
    if #EncounterPrep.TrapInstructions(beat) > 0 then
        bars[#bars + 1] = { id = "traps", level = StartingTrapsLevel(doc, beat) }
    end
    bars[#bars + 1] = { id = "stamina", level = 0 }

    local start = {}
    for _, bar in ipairs(bars) do
        start[bar.id] = bar.level
    end

    doc:BeginChange()
    doc.data.prep = {
        beatIndex = beatIndex,
        phase = "spending",
        bars = bars,
        start = start,
        spent = {},
        ready = {},
        requests = {},
        handled = {},
        startedAt = dmhub.serverTime,
        seq = 0,
    }
    doc.data.stageDismissAt = nil
    doc:CompleteChange("Tactical Preparation started", { undoable = false })

    printf("EotW preparation: started with %d Intelligence; surprise opens at %d (%s)",
        EncounterMontage.GetIntelligence(), start.surprise or 0,
        tostring(SURPRISE_LEVELS[(start.surprise or 0) + 1]))
    if not EncounterMontage.IsPresented() then
        EncounterMontage.Present(beatIndex)
    end
end

--Run the preparation from the host tick. Returns "running" while it plays
--and "done" once every player has proceeded and what they bought has landed.
function EncounterPrep.HostTick(script, beat, beatIndex)
    local doc = EncounterPrep.GetDoc()
    local m = doc.data.prep
    if type(m) ~= "table" or m.beatIndex ~= beatIndex then
        EncounterPrep.Begin(script, beat, beatIndex)
        return "running"
    end

    if m.phase == "done" then
        return "done"
    end

    if not EncounterMontage.IsPresented() then
        EncounterMontage.Present(beatIndex)
    end

    local heroes = EncounterMontage.Heroes()

    --requests, in a stable order (by time then userid), each at most once.
    local pending = {}
    for userid, req in pairs(m.requests or {}) do
        if type(req) == "table" and (tonumber(req.seq) or 0) > (tonumber((m.handled or {})[userid]) or 0) then
            pending[#pending + 1] = { userid = userid, req = req }
        end
    end
    table.sort(pending, function(a, b)
        local ta, tb = tonumber(a.req.time) or 0, tonumber(b.req.time) or 0
        if ta ~= tb then
            return ta < tb
        end
        return a.userid < b.userid
    end)

    local resetRequested = false
    doc:BeginChange()
    m = doc.data.prep
    for _, p in ipairs(pending) do
        m.handled = m.handled or {}
        m.handled[p.userid] = p.req.seq
        if p.req.kind == "reset" then
            resetRequested = true
        else
            local ok, result = pcall(HandleRequest, m, doc, p.userid, p.req, beat, heroes)
            if not ok then
                printf("EotW preparation: request %s from %s failed: %s", tostring(p.req.kind), tostring(p.userid), tostring(result))
            elseif result ~= nil then
                printf("EotW preparation: %s", tostring(result))
            end
        end
    end

    if m.phase == "spending" and ReadyComplete(m, heroes) then
        Resolve(m, doc, beat, heroes)
    end

    if m.phase == "resolved" then
        local age = dmhub.serverTime - (tonumber(m.resolvedAt) or dmhub.serverTime)
        if age >= RESOLVED_LINGER_SECONDS then
            m.phase = "done"
            m.doneAt = dmhub.serverTime
            m.seq = (tonumber(m.seq) or 0) + 1
            printf("EotW preparation: complete")
        end
    end

    if resetRequested then
        doc.data.prep = nil
    end
    doc:CompleteChange("Preparation tick", { undoable = false })

    if resetRequested then
        return "running"
    end
    if doc.data.prep ~= nil and doc.data.prep.phase == "done" then
        return "done"
    end
    return "running"
end

--Host: resolve on whoever has pressed Proceed (the dev command, and the
--answer to a player who has left the table).
function EncounterPrep.ForceResolve()
    local m = EncounterPrep.GetState()
    if m == nil or m.phase ~= "spending" then
        return false, "no preparation is waiting"
    end
    local script = EncounterMontage.FindMapScript()
    local beat = script.parse.beats[m.beatIndex or 0]
    if beat == nil then
        return false, "the script has moved on"
    end
    local doc = EncounterPrep.GetDoc()
    doc:BeginChange()
    Resolve(doc.data.prep, doc, beat, EncounterMontage.Heroes())
    doc:CompleteChange("Preparation: forced", { undoable = false })
    return true
end

--- dev driver ------------------------------------------------------------------

--Outside a real EotW game there is no map-script host tick, so
--"/eotwprep start" runs one here: the encounter beat of the current map's
--script, ticked every 0.5s until the party has finished preparing.
local m_devDriver = nil

function EncounterPrep.StartDevDriver()
    if m_devDriver ~= nil and m_devDriver.running then
        print("EotW preparation: dev driver already running")
        return
    end
    local driver = { running = true }
    m_devDriver = driver
    dmhub.Coroutine(function()
        while driver.running and not mod.unloaded do
            local script = EncounterMontage.FindMapScript()
            local beat, index = nil, nil
            for i, b in ipairs(script.parse.beats) do
                if b.kind == "encounter" then
                    beat, index = b, i
                    break
                end
            end
            if beat == nil then
                print("EotW preparation: this map's script has no encounter beat")
                break
            end
            local ok, status = pcall(EncounterPrep.HostTick, script, beat, index)
            if not ok then
                printf("EotW preparation: dev driver tick failed: %s", tostring(status))
            elseif status == "done" then
                print("EotW preparation: complete (dev driver)")
                break
            end
            coroutine.yield(0.5)
        end
        driver.running = false
    end)
    print("EotW preparation: dev driver started")
end

function EncounterPrep.StopDevDriver()
    if m_devDriver ~= nil then
        m_devDriver.running = false
    end
    m_devDriver = nil
end

--- dev command -----------------------------------------------------------------

local function PrintState()
    local m = EncounterPrep.GetState()
    if m == nil then
        printf("EotW preparation: nothing is running (Intelligence %s, feature %s)",
            tostring(EncounterMontage.GetIntelligence()),
            cond(EncounterPrep.Required(), "unlocked", "locked"))
        return
    end
    local script = EncounterMontage.FindMapScript()
    local beat = script.parse.beats[m.beatIndex or 0]
    printf("EotW preparation: beat %s, phase %s, %d Intelligence left",
        tostring(m.beatIndex), tostring(m.phase), EncounterMontage.GetIntelligence())
    for _, bar in ipairs(m.bars or {}) do
        local info = EncounterPrep.BarInfo(beat, bar.id)
        printf("  %s: level %d of %d (opened at %s) -- %s", info.title, bar.level,
            #info.levels - 1, tostring((m.start or {})[bar.id]), tostring(info.levels[(bar.level or 0) + 1]))
    end
    for _, voter in ipairs(EncounterPrep.Voters(nil)) do
        printf("  %s: %s, %d Intelligence to spend", tostring(voter.name),
            cond((m.ready or {})[voter.key] ~= nil, "ready", "still preparing"),
            EncounterMontage.SpendableIntelligence(voter.heroids))
    end
    for _, line in ipairs(m.applied or {}) do
        printf("  applied: %s", tostring(line))
    end
end

pcall(function()
    Commands.RegisterMacro{
        name = "eotwprep",
        summary = "inspect or drive the Encounter of the Week Tactical Preparation screen",
        doc = "Usage: /eotwprep start | stop | state | force | reset | unlock | intelligence <n>\nstart runs the encounter beat's preparation right here (a dev host tick, for the authoring game); stop halts that driver; state prints the bars and who is ready; force resolves on the players already ready; reset clears the preparation state so the encounter beat opens it again; unlock turns the Intelligence feature on without a script; intelligence <n> sets the party's pool, split evenly across the heroes.",
        command = function(str)
            local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
            local amount = string.match(arg, "^intelligence%s+(%-?%d+)$")
            if arg == "start" then
                EncounterPrep.StartDevDriver()
            elseif arg == "stop" then
                EncounterPrep.StopDevDriver()
                print("EotW preparation: dev driver stopped")
            elseif arg == "force" then
                local ok, err = EncounterPrep.ForceResolve()
                printf("EotW preparation: force -> %s", tostring(ok and "resolved" or err))
            elseif arg == "reset" then
                local doc = EncounterPrep.GetDoc()
                doc:BeginChange()
                doc.data.prep = nil
                doc:CompleteChange("Preparation reset", { undoable = false })
                print("EotW preparation: state cleared")
            elseif amount ~= nil then
                local doc = EncounterPrep.GetDoc()
                doc:BeginChange()
                --start from nothing, then credit it the way a party-wide
                --award lands, so every hero holds an even share.
                doc.data.intelligence = 0
                doc.data.intelligenceByHero = {}
                local heroes = EncounterMontage.Heroes()
                local n = tonumber(amount) or 0
                local credits = EncounterMontage.SplitIntelligence(doc, heroes, n)
                EncounterMontage.CreditIntelligence(doc, credits, "/eotwprep", "Intelligence set",
                    cond(#credits == 0, n, 0))
                doc:CompleteChange("Intelligence set", { undoable = false })
                printf("EotW preparation: the party has %s Intelligence", tostring(amount))
            elseif arg == "unlock" then
                local doc = EncounterPrep.GetDoc()
                doc:BeginChange()
                EncounterMontage.UnlockFeature(doc, "intelligence", "/eotwprep unlock")
                doc:CompleteChange("Intelligence unlocked", { undoable = false })
                print("EotW preparation: Intelligence unlocked")
            elseif arg == "json" then
                print(json(EncounterPrep.GetState()))
            else
                PrintState()
            end
        end,
    }
end)
