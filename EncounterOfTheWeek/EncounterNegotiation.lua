--Encounter of the Week: the negotiation runtime.
--
--Runs a "# Negotiation: <NPC>" beat of the map's script (EncounterScript.lua)
--with no Director. Heroes pick authored arguments, each secretly tagged to a
--motivation, a pitfall or nothing; NegotiationRules applies the book's rules.
--
--Design: NEGOTIATION_SCRIPTED_PLAN.md in the dmhub repo.
--
--Authority model is the montage's: the HOST is the single writer of
--negotiation.* state, from the map script's host tick. Players only stamp
--negotiation.requests[userid] and the host validates them in order. The
--acting player's client rolls (ClientTick) and reports the tier as a request.
--
--The shared document is the montage's ("eotwscript"), under its own key:
--  data.negotiation = {
--    beatIndex, seq,
--    phase = "arriving"|"choosing"|"rolling"|"reply"|"voting"|"final"|"done",
--    interest, patience,
--    learned = { [traitId] = true },     -- what the party knows
--    usedTraits = { [traitId] = true },  -- motivations already appealed to
--    usedArguments = { [argumentId] = true },
--    spoke = { [charid] = n },
--    canRead,                            -- false after a read, until an argument
--    turn = nil | { kind = "argue"|"read", argumentId, heroid, heroName, userid,
--                   rollSeq, noDice, wants },
--    last = nil | { kind, argumentId, heroName, tier, total, track, reply, cue,
--                   interest, patience, found },
--    replyAt, afterReply = nil|"final"|"nodeal",
--    votes = { [voterKey] = { choice, userid } }, voteOptions = { "deal", ... },
--    result = nil | { outcome = "deal"|"refused"|"nodeal", interest, applied },
--    requests = { [userid] = { seq, kind, ... } }, handled = { [userid] = seq },
--    log = { { heroName, text }, ... },
--    startedAt, doneAt,
--  }

local mod = dmhub.GetModLoading()

local T = UIText.T

EncounterNegotiation = rawget(_G, "EncounterNegotiation") or {}

local DOC_ID = "eotwscript"

--how long an NPC's reply stays up if nobody presses on.
local REPLY_SECONDS = 12
--and how long the finished negotiation holds before the script moves on.
local DONE_LINGER_SECONDS = 6
--what a hint costs, before the first argument (see SpendClue).
local CLUE_COST = 1
--the book's discovery test: any of the three, whichever suits the hero.
local READ_ATTR = "Reason, Intuition or Presence"

--- the document ------------------------------------------------------------

function EncounterNegotiation.GetDoc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

--The live state, or nil when no negotiation beat is running.
function EncounterNegotiation.GetState()
    local m = nil
    pcall(function() m = mod:GetDocumentSnapshot(DOC_ID).data.negotiation end)
    if type(m) ~= "table" then
        return nil
    end
    return m
end

function EncounterNegotiation.CurrentBeat()
    local preview = EncounterNegotiation.PreviewBeat()
    if preview ~= nil then
        return preview, nil
    end
    local m = EncounterNegotiation.GetState()
    if m == nil then
        return nil, nil
    end
    local script = EncounterMontage.FindMapScript()
    local beat = script.parse.beats[m.beatIndex or 0]
    if beat == nil or beat.kind ~= "negotiation" then
        return nil, script
    end
    return beat, script
end

local function FindById(list, id)
    for _, item in ipairs(list or {}) do
        if item.id == id then
            return item
        end
    end
    return nil
end

function EncounterNegotiation.Argument(beat, id)
    return FindById(beat.arguments, id)
end

function EncounterNegotiation.Trait(beat, id)
    return FindById(beat.traits, id)
end

--- facts ---------------------------------------------------------------------

--The rider verdict for a hero on an argument: its edges, and whether a secret
--argument is theirs to make.
function EncounterNegotiation.Verdict(charid, argument)
    if #(argument.riders or {}) == 0 then
        return nil
    end
    local verdict = nil
    local ok, err = pcall(function()
        verdict = EncounterScript.EvaluateRiders(argument.riders, EncounterMontage.HeroFacts(charid))
    end)
    if not ok then
        printf("EotW negotiation: rider verdict failed: %s", tostring(err))
    end
    return verdict
end

--May this hero make this argument? A secret one is hidden from everyone else.
function EncounterNegotiation.CanMakeArgument(charid, argument)
    local verdict = EncounterNegotiation.Verdict(charid, argument)
    return verdict == nil or verdict.allowed ~= false
end

--The book's language rule: one speaker of the NPC's native language adds 1
--patience at the start, three or more add 2, to a maximum of 5. Caelian, the
--common tongue, never counts.
local function LanguageBonus(beat, heroes)
    if beat.language == "" or string.lower(beat.language) == "caelian" then
        return 0
    end
    local requirement = EncounterScript.ParseRequirement("you speak " .. beat.language)
    local speakers = 0
    for _, hero in ipairs(heroes) do
        local met = false
        pcall(function()
            met = EncounterScript.RequirementMet(requirement, EncounterMontage.HeroFacts(hero.charid)) and true or false
        end)
        if met then
            speakers = speakers + 1
        end
    end
    if speakers >= 3 then
        return 2
    end
    return speakers >= 1 and 1 or 0
end

--- requests (player side) ---------------------------------------------------

--Stamp a request for the host: {seq, kind, ...args}. One slot per user; a
--newer request replaces an unhandled older one.
function EncounterNegotiation.SendRequest(kind, args)
    local userid = dmhub.loginUserid
    local doc = EncounterNegotiation.GetDoc()
    if doc.data.negotiation == nil then
        return false
    end
    doc:BeginChange()
    local m = doc.data.negotiation
    m.requests = m.requests or {}
    local prev = m.requests[userid]
    local req = { seq = ((prev ~= nil and prev.seq) or 0) + 1, kind = kind, time = dmhub.serverTime }
    for k, v in pairs(args or {}) do
        req[k] = v
    end
    m.requests[userid] = req
    doc:CompleteChange("Negotiation request: " .. tostring(kind), { undoable = false })
    return true
end

--- host: the rules -----------------------------------------------------------

local function UserControlsHero(userid, hero)
    return hero ~= nil and (hero.ownerId == userid or hero.ownerId == "PARTY")
end

local function FindHero(heroes, charid)
    for _, hero in ipairs(heroes) do
        if hero.charid == charid then
            return hero
        end
    end
    return nil
end

local function Bump(m)
    m.seq = (tonumber(m.seq) or 0) + 1
end

--An argument's reply: the author's line for how it went, else the book's stock
--response for a rise, a fall or impatience.
local function ReplyFor(argument, delta, track, repeated)
    if track == "pitfall" then
        return argument.backfires ~= "" and argument.backfires or T("negotiation.reply.negative")
    end
    if delta.interest > 0 then
        return argument.lands ~= "" and argument.lands or T("negotiation.reply.positive")
    end
    if delta.interest < 0 then
        return argument.backfires ~= "" and argument.backfires or T("negotiation.reply.negative")
    end
    if repeated then
        return T("negotiation.reply.impatient")
    end
    return argument.fallsShort ~= "" and argument.fallsShort or T("negotiation.reply.impatient")
end

--Move on from an argument or a read: show the reply, and note whether the
--talking has ended (NegotiationRules decides that).
local function AfterMeters(m)
    local terminal = NegotiationRules.Terminal(m.interest, m.patience)
    m.afterReply = nil
    if terminal == "nodeal" then
        m.afterReply = "nodeal"
    elseif terminal == "final" then
        m.afterReply = "final"
    end
    m.turn = nil
    m.phase = "reply"
    m.replyAt = dmhub.serverTime
    Bump(m)
end

--Apply an argument under the book's rules. A pitfall fails whatever is
--rolled, so it reaches here with no tier.
local function ResolveArgument(m, beat, argument, hero, tier, total, natural)
    local track = "nomotivation"
    local repeated = false
    if argument.kind == "pitfall" then
        track = "pitfall"
    elseif argument.kind == "motivation" then
        track = "appeal"
        repeated = (m.usedTraits or {})[argument.traitId] == true
    else
        repeated = (m.usedArguments or {})[argument.id] == true
    end

    local delta = NegotiationRules.Resolve{
        track = track,
        tier = tier or 1,
        repeated = repeated,
        natHigh = natural ~= nil and natural >= 19,
    }
    m.interest, m.patience = NegotiationRules.ApplyDelta(m.interest, m.patience, delta)

    m.usedArguments = m.usedArguments or {}
    m.usedArguments[argument.id] = true
    m.learned = m.learned or {}
    if argument.traitId ~= nil then
        m.learned[argument.traitId] = true
        if track == "appeal" then
            m.usedTraits = m.usedTraits or {}
            m.usedTraits[argument.traitId] = true
        end
    end
    m.spoke = m.spoke or {}
    m.spoke[hero.charid] = (tonumber(m.spoke[hero.charid]) or 0) + 1
    m.canRead = true
    m.split = nil

    m.last = {
        kind = "argue",
        argumentId = argument.id,
        heroName = hero.name,
        tier = tier,
        total = total,
        track = track,
        reply = ReplyFor(argument, delta, track, repeated),
        interest = delta.interest,
        patience = delta.patience,
    }
    m.log = m.log or {}
    m.log[#m.log + 1] = { heroName = hero.name, text = argument.name, track = track, tier = tier }
    AfterMeters(m)
end

--Read the NPC, under the book's discovery test: tier 1 costs patience, tier 3
--reveals one motivation or pitfall of the hero's choice of kind.
local function ResolveRead(m, beat, hero, tier, total, wants)
    local found = nil
    if tier >= 3 then
        local kinds = wants == "pitfall" and { "pitfall", "motivation" } or { "motivation", "pitfall" }
        for _, kind in ipairs(kinds) do
            for _, trait in ipairs(beat.traits) do
                if found == nil and trait.kind == kind and not (m.learned or {})[trait.id] then
                    found = trait
                end
            end
        end
    end
    if found ~= nil then
        m.learned = m.learned or {}
        m.learned[found.id] = true
    end
    if tier <= 1 then
        m.patience = math.max(0, m.patience - 1)
    end
    m.spoke = m.spoke or {}
    m.spoke[hero.charid] = (tonumber(m.spoke[hero.charid]) or 0) + 1
    m.canRead = false
    m.split = nil
    m.last = {
        kind = "read",
        heroName = hero.name,
        tier = tier,
        total = total,
        found = found ~= nil and found.id or nil,
    }
    AfterMeters(m)
end

--A copy of an offer's effects aimed at the whole party: a deal is the party's,
--as an agreed narrative option is.
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

--End the negotiation. A refused offer applies nothing; a deal, or the
--"No, and..." of interest 0, applies its offer's rules.
local function Finish(m, doc, beat, outcome)
    local heroes = EncounterMontage.Heroes()
    local anchor = heroes[1]
    local offer = beat.offers[m.interest + 1]
    local applied = {}
    if outcome ~= "refused" and offer ~= nil and not m.rehearsal then
        local newAllies = nil
        applied, newAllies = EncounterMontage.ApplyEffects(PartyScoped(offer.effects), {
            heroEntry = anchor,
            userid = anchor ~= nil and anchor.ownerId or nil,
            entryName = beat.name,
            source = T("negotiation.effect_source"),
            splitIntelligence = true,
            doc = doc,
        })
        for _, charid in ipairs(newAllies or {}) do
            EncounterMontage.RecordAlly(doc, anchor.charid, charid)
        end
    end
    m.result = { outcome = outcome, interest = m.interest, applied = applied }
    m.turn = nil
    m.votes = nil
    m.voteOptions = nil
    m.phase = "done"
    m.doneAt = dmhub.serverTime
    Bump(m)
    printf("EotW negotiation: over (%s at interest %d)", tostring(outcome), m.interest)
    EotwAnalytics.Track("eotw_negotiation_end", {
        npc = beat.name,
        outcome = outcome,
        interest = m.interest,
        patience = m.patience,
        arguments = #(m.log or {}),
    })
end

local function OpenVote(m, phase, options)
    m.phase = phase
    m.votes = {}
    m.voteOptions = options
    Bump(m)
end

--Everyone has voted: an agreed choice stands, and a split one is settled by a
--random player, as a split narrative choice is.
local function SettleVote(m, doc, beat, heroes)
    local voters = EncounterNarrative.Voters(nil, heroes)
    local picks = {}
    local agreed = true
    for _, voter in ipairs(voters) do
        local vote = (m.votes or {})[voter.key]
        if vote == nil then
            return
        end
        agreed = agreed and (#picks == 0 or picks[1].choice == vote.choice)
        picks[#picks + 1] = { choice = vote.choice, name = voter.name }
    end
    if #picks == 0 then
        return
    end
    local pick = picks[math.random(#picks)]
    local choice = pick.choice
    m.split = cond(agreed, nil, pick.name)
    if choice == "talk" then
        m.phase = "choosing"
        m.votes = nil
        m.voteOptions = nil
        Bump(m)
    else
        Finish(m, doc, beat, choice == "deal" and "deal" or "refused")
    end
end

--The players a vote is still waiting for, as display names.
function EncounterNegotiation.PendingVoters(m)
    local pending = {}
    for _, voter in ipairs(EncounterNarrative.Voters(nil, EncounterMontage.Heroes())) do
        if (m.votes or {})[voter.key] == nil then
            pending[#pending + 1] = voter.name
        end
    end
    return pending
end

--Host only. Heroes changed hands: as EncounterMontage.SyncTurnToOwners, a roll
--out stays with its roller unless that player is in `away`, and the hero's new
--controller then rolls it afresh. Returns true when the turn changed.
function EncounterNegotiation.SyncTurnToOwners(away)
    away = away or {}
    local doc = EncounterNegotiation.GetDoc()
    local m = doc.data.negotiation
    if type(m) ~= "table" or type(m.turn) ~= "table" or not away[m.turn.userid] then
        return false
    end
    local tok = dmhub.GetCharacterById(m.turn.heroid)
    local owner = tok ~= nil and tok.ownerId or nil
    if owner == nil or owner == "PARTY" or owner == m.turn.userid then
        return false
    end
    doc:BeginChange()
    m = doc.data.negotiation
    printf("EotW negotiation: %s's roll passes from %s to %s", tostring(m.turn.heroName), tostring(m.turn.userid), owner)
    m.turn.userid = owner
    Bump(m)
    doc:CompleteChange("Negotiation: the roll changes hands", { undoable = false })
    return true
end

--- host: requests -------------------------------------------------------------

--The next trait the party has not learned, motivations first.
function EncounterNegotiation.NextHiddenTrait(m, beat)
    for _, kind in ipairs({ "motivation", "pitfall" }) do
        for _, trait in ipairs(beat.traits) do
            if trait.kind == kind and not (m.learned or {})[trait.id] then
                return trait
            end
        end
    end
    return nil
end

--May Intelligence buy a hint now? Before the first argument only: this is the
--book's research ahead of the talk, not a way out of a bad one.
function EncounterNegotiation.CanSpendClue(m, beat)
    return m.phase == "choosing" and #(m.log or {}) == 0 and EncounterMontage.FeatureUnlocked("intelligence")
        and EncounterNegotiation.NextHiddenTrait(m, beat) ~= nil
end

--Spend the player's Intelligence on what the party found out on the way here.
local function SpendClue(m, doc, userid, beat, heroes)
    if not EncounterNegotiation.CanSpendClue(m, beat) then
        return nil
    end
    local heroids, names = {}, {}
    for _, hero in ipairs(heroes) do
        names[hero.charid] = hero.name
        if UserControlsHero(userid, hero) then
            heroids[#heroids + 1] = hero.charid
        end
    end
    local ok, from = EncounterMontage.SpendIntelligence(doc, heroids, CLUE_COST, names)
    if not ok then
        return string.format("%s spent Intelligence they do not have", tostring(userid))
    end
    local trait = EncounterNegotiation.NextHiddenTrait(m, beat)
    ---@cast trait -nil
    m.learned = m.learned or {}
    m.learned[trait.id] = true
    local log = doc.data.intelligenceLog or {}
    log[#log + 1] = {
        value = tonumber(doc.data.intelligence) or 0,
        amount = -CLUE_COST,
        who = names[heroids[1]] or tostring(userid),
        note = T("negotiation.intelligence_log", { npc = beat.name, heroes = table.concat(from or {}, ", ") }),
        at = dmhub.serverTime,
    }
    doc.data.intelligenceLog = log
    m.last = { kind = "clue", found = trait.id }
    Bump(m)
    return string.format("Intelligence revealed %s", trait.name)
end

local function HandleRequest(m, doc, userid, req, beat, heroes)
    local kind = req.kind

    if kind == "spendClue" then
        return SpendClue(m, doc, userid, beat, heroes)
    end

    if kind == "argue" or kind == "read" then
        if m.phase ~= "choosing" then
            return nil
        end
        local hero = FindHero(heroes, req.heroid)
        if not UserControlsHero(userid, hero) then
            return string.format("%s does not control hero %s", tostring(userid), tostring(req.heroid))
        end
        ---@cast hero -nil
        if kind == "read" then
            if not m.canRead then
                return string.format("%s cannot read the NPC again before an argument", hero.name)
            end
            m.phase = "rolling"
            Bump(m)
            m.turn = { kind = "read", heroid = hero.charid, heroName = hero.name, userid = userid,
                rollSeq = m.seq, noDice = req.noDice, wants = req.wants }
            return string.format("%s reads the NPC", hero.name)
        end
        local argument = EncounterNegotiation.Argument(beat, req.argumentId)
        if argument == nil then
            return string.format("no argument '%s'", tostring(req.argumentId))
        end
        if not EncounterNegotiation.CanMakeArgument(hero.charid, argument) then
            return string.format("%s may not make '%s'", hero.name, argument.name)
        end
        if argument.kind == "pitfall" then
            ResolveArgument(m, beat, argument, hero, nil, nil, nil)
            return string.format("%s hit a pitfall with '%s'", hero.name, argument.name)
        end
        m.phase = "rolling"
        Bump(m)
        m.turn = { kind = "argue", argumentId = argument.id, heroid = hero.charid, heroName = hero.name,
            userid = userid, rollSeq = m.seq, noDice = req.noDice }
        return string.format("%s argues '%s'", hero.name, argument.name)
    end

    if kind == "rolled" or kind == "rollCancelled" then
        local t = m.turn
        if m.phase ~= "rolling" or t == nil or t.userid ~= userid or t.rollSeq ~= req.rollSeq then
            return nil
        end
        if kind == "rollCancelled" then
            m.turn = nil
            m.phase = "choosing"
            Bump(m)
            return "the roll was cancelled"
        end
        local hero = FindHero(heroes, t.heroid)
        local tier = math.max(1, math.min(3, tonumber(req.tier) or 1))
        if hero == nil then
            m.turn = nil
            m.phase = "choosing"
            return "the rolling hero has gone"
        end
        if t.kind == "read" then
            ResolveRead(m, beat, hero, tier, req.total, t.wants)
        else
            ResolveArgument(m, beat, EncounterNegotiation.Argument(beat, t.argumentId), hero, tier, req.total, req.natural)
        end
        return string.format("%s rolled tier %d", hero.name, tier)
    end

    if kind == "continue" then
        if m.phase == "reply" then
            m.replyAt = 0
        elseif m.phase == "done" then
            m.doneAt = 0
        end
        return nil
    end

    --stopping is the party's choice: anyone may propose taking the deal on the
    --table, and every player then answers.
    if kind == "takeDeal" then
        if m.phase ~= "choosing" or m.interest < 1 then
            return nil
        end
        OpenVote(m, "voting", { "deal", "talk" })
    end

    if kind == "takeDeal" or kind == "vote" then
        if m.phase ~= "voting" and m.phase ~= "final" then
            return nil
        end
        local key = EncounterNarrative.VoterKeyForUser(userid, heroes)
        if key == nil then
            return string.format("%s controls no hero and cannot vote", tostring(userid))
        end
        local choice = kind == "takeDeal" and "deal" or req.choice
        local known = false
        for _, option in ipairs(m.voteOptions or {}) do
            known = known or option == choice
        end
        if not known then
            return string.format("'%s' is not on the vote", tostring(choice))
        end
        m.votes = m.votes or {}
        m.votes[key] = { choice = choice, userid = userid }
        Bump(m)
        return nil
    end

    return nil
end

--- host: the beat -------------------------------------------------------------

--Seed the state for a negotiation beat. The beat opens in "arriving": nobody
--can act until the host tick, which runs once every player is in. A rehearsal
--plays the same but its deal applies nothing.
function EncounterNegotiation.Begin(script, beat, beatIndex, rehearsal)
    local attitude = NegotiationRules.AttitudeById(beat.attitude)
    local heroes = EncounterMontage.Heroes()
    local patience = math.min(NegotiationRules.MAX, attitude.patience + LanguageBonus(beat, heroes))
    local doc = EncounterNegotiation.GetDoc()
    local clues = doc.data.negotiationClues or {}
    local learned = {}
    for _, trait in ipairs(beat.traits) do
        if trait.start == "known" or (trait.start == "unlock" and clues[EncounterScript.MatchKey(trait.unlock)]) then
            learned[trait.id] = true
        end
    end
    doc:BeginChange()
    doc.data.negotiation = {
        beatIndex = beatIndex,
        phase = "arriving",
        rehearsal = rehearsal,
        interest = attitude.interest,
        patience = patience,
        startPatience = attitude.patience,
        learned = learned,
        usedTraits = {},
        usedArguments = {},
        spoke = {},
        canRead = true,
        requests = {},
        handled = {},
        log = {},
        startedAt = dmhub.serverTime,
        seq = 0,
    }
    doc.data.stageDismissAt = nil
    doc:CompleteChange("Negotiation started", { undoable = false })
    printf("EotW negotiation: beat %d started with %s (interest %d, patience %d)", beatIndex, tostring(beat.name), attitude.interest, patience)
    EncounterMontage.Present(beatIndex)
end

--Run the negotiation beat from the host tick. Returns "running" while it plays
--and "done" once it is over.
function EncounterNegotiation.HostTick(script, beat, beatIndex)
    local doc = EncounterNegotiation.GetDoc()
    local m = doc.data.negotiation
    if type(m) ~= "table" or m.beatIndex ~= beatIndex then
        EncounterNegotiation.Begin(script, beat, beatIndex)
        return "running"
    end

    if not EncounterMontage.IsPresented() then
        EncounterMontage.Present(beatIndex)
    end

    local heroes = EncounterMontage.Heroes()

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
    m = doc.data.negotiation
    if m.phase == "arriving" then
        m.phase = "choosing"
        m.startedAt = dmhub.serverTime
        Bump(m)
    end
    for _, p in ipairs(pending) do
        m.handled = m.handled or {}
        m.handled[p.userid] = p.req.seq
        if p.req.kind == "reset" then
            resetRequested = true
        else
            local ok, result = pcall(HandleRequest, m, doc, p.userid, p.req, beat, heroes)
            if not ok then
                printf("EotW negotiation: request %s from %s failed: %s", tostring(p.req.kind), tostring(p.userid), tostring(result))
            elseif result ~= nil then
                printf("EotW negotiation: %s", tostring(result))
            end
        end
    end

    --every tick, not only on a vote: a player who leaves stops being a voter
    --when the host takes their heroes, and that can complete the vote.
    if m.phase == "voting" or m.phase == "final" then
        SettleVote(m, doc, beat, heroes)
    end

    --the reply has been read: back to the table, or on to how it ended.
    if m.phase == "reply" then
        local age = dmhub.serverTime - (tonumber(m.replyAt) or 0)
        if age >= REPLY_SECONDS then
            if m.afterReply == "nodeal" then
                Finish(m, doc, beat, "nodeal")
            elseif m.afterReply == "final" then
                OpenVote(m, "final", { "deal", "refuse" })
            else
                m.phase = "choosing"
                Bump(m)
            end
        end
    end

    if resetRequested then
        doc.data.negotiation = nil
    end
    doc:CompleteChange("Negotiation tick", { undoable = false })

    if resetRequested then
        return "running"
    end
    m = doc.data.negotiation
    if m ~= nil and m.phase == "done" then
        local age = dmhub.serverTime - (tonumber(m.doneAt) or 0)
        if age >= DONE_LINGER_SECONDS then
            return "done"
        end
    end
    return "running"
end

--- client: the roll -----------------------------------------------------------

local m_launchedRollSeq = nil

--The acting player's client shows the roll: the same dialog as a montage test,
--with the argument's skills and the hero's edges.
function EncounterNegotiation.ClientTick()
    local m = EncounterNegotiation.GetState()
    if m == nil or m.turn == nil or m.phase ~= "rolling" then
        m_launchedRollSeq = nil
        return
    end
    local t = m.turn
    if t.noDice or t.userid ~= dmhub.loginUserid or m_launchedRollSeq == t.rollSeq then
        return
    end
    local beat = EncounterNegotiation.CurrentBeat()
    local heroToken = dmhub.GetCharacterById(t.heroid)
    if beat == nil or heroToken == nil or not heroToken.valid then
        return
    end
    m_launchedRollSeq = t.rollSeq

    local attr = READ_ATTR
    local name = T("negotiation.roll.read_name")
    local verdict = nil
    if t.kind == "argue" then
        local argument = EncounterNegotiation.Argument(beat, t.argumentId)
        if argument == nil or argument.roll == nil then
            return
        end
        attr = argument.roll.attr
        name = argument.name
        verdict = EncounterNegotiation.Verdict(t.heroid, argument)
    end
    local rollSeq = t.rollSeq
    local parts = EncounterMontage.BuildTestRoll(heroToken, attr, name, verdict)
    EncounterMontage.ShowTestRoll{
        creature = heroToken.properties,
        heroToken = heroToken,
        title = parts.title,
        rollType = parts.rollType,
        roll = parts.roll,
        modifiers = parts.modifiers,
        tiers = { T("negotiation.roll.tier1"), T("negotiation.roll.tier2"), T("negotiation.roll.tier3") },
        rollSeq = rollSeq,
        completeKind = "rolled",
        cancelKind = "rollCancelled",
        stillWanted = function()
            local live = EncounterNegotiation.GetState()
            return live ~= nil and live.turn ~= nil and live.phase == "rolling" and live.turn.rollSeq == rollSeq
        end,
        send = EncounterNegotiation.SendRequest,
        onNotShown = function()
            m_launchedRollSeq = nil
        end,
    }
end

--- dev driver ----------------------------------------------------------------

--Outside a real EotW game there is no map-script host tick, so
--"/eotwnegotiation start" runs one here.
local m_devDriver = nil

function EncounterNegotiation.StartDevDriver()
    if m_devDriver ~= nil and m_devDriver.running then
        print("EotW negotiation: dev driver already running")
        return
    end
    local driver = { running = true }
    m_devDriver = driver
    dmhub.Coroutine(function()
        while driver.running and not mod.unloaded do
            local script = EncounterMontage.FindMapScript()
            local beat, index = nil, nil
            for i, b in ipairs(script.parse.beats) do
                if b.kind == "negotiation" then
                    beat, index = b, i
                    break
                end
            end
            if beat == nil then
                print("EotW negotiation: this map's script has no negotiation beat")
                break
            end
            local ok, status = pcall(EncounterNegotiation.HostTick, script, beat, index)
            if not ok then
                printf("EotW negotiation: dev driver tick failed: %s", tostring(status))
            elseif status == "done" then
                print("EotW negotiation: finished (dev driver)")
                break
            end
            pcall(EncounterNegotiation.ClientTick)
            coroutine.yield(0.5)
        end
        driver.running = false
    end)
    print("EotW negotiation: dev driver started")
end

function EncounterNegotiation.StopDevDriver()
    if m_devDriver ~= nil then
        m_devDriver.running = false
    end
    m_devDriver = nil
end

--- preview ---------------------------------------------------------------------

--"/eotwnegotiation preview" plays this scene on the real stage with no journal
--document, over whatever the map's script is doing.
local PREVIEW_SCRIPT = [==[
# Negotiation: Hask

Played by: Human Bandit Chief
Pronouns: he
Attitude: Suspicious
Language: Zaliac
Want: Get the party across before the Golden Hand arrives.
Opening: Bridge is closed. Toll is what I say it is. You have got until I lose interest, so talk.

## Motivation: Greed
Clue: He never takes his hand off the strongbox.

## Motivation: Protection
Clue: Two fresh graves by the bridgehead. He looks at them often.

## Pitfall: Higher Authority
Clue: Hask answers to no one. Lord or baron, he does not care.
Start: Known

## Pitfall: Justice

## Argument: Offer him a cut of what the road earns
Appeals: Greed
PC: There is more in this road than you are collecting.
|Test: Presence (Persuade)
|Edge: you speak Zaliac
Lands: Now that is a sound I know. Say it again, slower.
Falls short: A share of what? Show me coin, not promises.

## Argument: Promise to drive the Golden Hand off his road
Appeals: Protection
PC: They took two of your crew last month.
|Test: Reason (Lead)
Lands: You know about that? Then you know what it would mean to my people.
Falls short: Plenty have promised that. They are buried by the ford.

## Argument: Show him the baron's writ of passage
Appeals: Higher Authority
PC: By order of the baron, this bridge stands open to us.
Fails: The baron is three days away and I am standing right here.

## Argument: Call the toll what it is: theft
Appeals: Justice
PC: This is robbery with a gate on it.
Fails: Justice is for people with walls. I have a bridge.

## Argument: Share a drink with his crew
Appeals: Nothing
PC: Long night on a cold bridge.
|Test: Presence (Flirt)
Lands: Ha! All right, that earns you a hearing.
Falls short: Drink your own. I am working.
Backfires: You think I can be bought with a skin of bad wine?

## Argument: Tell him how the songs will remember this
Appeals: Nothing
PC: One day they will sing of the captain who held this ford.
|Test: Intuition (Brag)
Lands: Heh. Nobody has ever sung about me.
Falls short: The dead do not hear songs.
Backfires: Save it for a tavern, poet.

## Argument: Swear on the old road
Appeals: Protection
|Allow: you speak Zaliac
|Test: Intuition (Persuade)
Lands: I have not heard that oath since my father died. You mean it.
Falls short: Old words. Nobody keeps those any more.

## Offer: No, and
He bars the bridge and sends word to the Golden Hand.

## Offer: No
Nobody crosses tonight.

## Offer: No, but
He will not open the bridge, but he will point out the ford upstream.

## Offer: Yes, but
You may cross, for 20 gold a head.

## Offer: Yes
You may cross, free of charge.

## Offer: Yes, and
You may cross, and two of his crew come with you as guides.
]==]

local m_previewBeat = nil

function EncounterNegotiation.PreviewBeat()
    return m_previewBeat
end

--`beat` plays that beat instead: the builder's "Test this negotiation".
function EncounterNegotiation.StartPreview(beat)
    if beat == nil then
        local parsed = EncounterScript.Parse(PREVIEW_SCRIPT)
        if #parsed.warnings > 0 then
            printf("EotW negotiation: preview script: %s", tostring(parsed.warnings[1]))
        end
        beat = parsed.beats[1]
    end
    m_previewBeat = beat
    local driver = { running = true }
    m_devDriver = driver
    EncounterNegotiation.Begin(nil, beat, 1, true)
    dmhub.Coroutine(function()
        while driver.running and not mod.unloaded and m_previewBeat == beat do
            local ok, status = pcall(EncounterNegotiation.HostTick, nil, beat, 1)
            if not ok then
                printf("EotW negotiation: preview tick failed: %s", tostring(status))
            elseif status == "done" then
                break
            end
            coroutine.yield(0.5)
        end
        driver.running = false
        if m_previewBeat == beat then
            EncounterNegotiation.StopPreview()
        end
    end)
end

function EncounterNegotiation.StopPreview()
    if m_previewBeat == nil then
        return
    end
    m_previewBeat = nil
    EncounterMontage.Hide()
    local doc = EncounterNegotiation.GetDoc()
    doc:BeginChange()
    doc.data.negotiation = nil
    doc:CompleteChange("Negotiation preview ended", { undoable = false })
end

--- dev commands --------------------------------------------------------------

local function PrintState()
    local m = EncounterNegotiation.GetState()
    if m == nil then
        print("EotW negotiation: no negotiation is running")
        return
    end
    local beat = EncounterNegotiation.CurrentBeat()
    printf("EotW negotiation: phase %s, interest %d, patience %d, can read %s",
        tostring(m.phase), m.interest, m.patience, tostring(m.canRead))
    if m.last ~= nil then
        printf("  last: %s by %s, tier %s: %s", tostring(m.last.kind), tostring(m.last.heroName), tostring(m.last.tier), tostring(m.last.reply))
    end
    if m.result ~= nil then
        printf("  result: %s at interest %d, %d applied", tostring(m.result.outcome), m.result.interest, #(m.result.applied or {}))
    end
    if beat ~= nil then
        for i, argument in ipairs(beat.arguments) do
            printf("  argument %d: %s (%s)", i, argument.name, argument.kind)
        end
        for _, trait in ipairs(beat.traits) do
            printf("  %s %s: %s", trait.kind, trait.name, cond((m.learned or {})[trait.id], "learned", "hidden"))
        end
    end
end

--Hero by 1-based position in the party.
local function DevHero(text)
    local hero = EncounterMontage.Heroes()[tonumber(text) or 1]
    return hero ~= nil and hero.charid or nil
end

pcall(function()
    Commands.RegisterMacro{
        name = "eotwnegotiation",
        summary = "inspect, drive or reset the Encounter of the Week negotiation beat",
        doc = "Usage: /eotwnegotiation preview | endpreview | start | stop | state | argue <n> <hero> | read <hero> | tier <1-3> | continue | deal | vote <choice> | reset\nstart runs this map's first negotiation beat here; argue and read skip the dice, and tier reports the roll.",
        command = function(str)
            local words = {}
            for word in string.gmatch(str or "", "%S+") do
                words[#words + 1] = word
            end
            local arg = string.lower(words[1] or "")
            if arg == "start" then
                EncounterNegotiation.StartDevDriver()
            elseif arg == "preview" then
                EncounterNegotiation.StartPreview()
            elseif arg == "endpreview" then
                EncounterNegotiation.StopPreview()
            elseif arg == "stop" then
                EncounterNegotiation.StopDevDriver()
            elseif arg == "argue" then
                local beat = EncounterNegotiation.CurrentBeat()
                local argument = beat ~= nil and beat.arguments[tonumber(words[2]) or 0] or nil
                if argument == nil then
                    print("EotW negotiation: no such argument")
                    return
                end
                EncounterNegotiation.SendRequest("argue", { argumentId = argument.id, heroid = DevHero(words[3]), noDice = true })
            elseif arg == "read" then
                EncounterNegotiation.SendRequest("read", { heroid = DevHero(words[2]), noDice = true, wants = words[3] })
            elseif arg == "tier" then
                local m = EncounterNegotiation.GetState()
                local turn = m ~= nil and m.turn or nil
                EncounterNegotiation.SendRequest("rolled", { rollSeq = turn ~= nil and turn.rollSeq or nil, tier = tonumber(words[2]) or 1 })
            elseif arg == "continue" then
                EncounterNegotiation.SendRequest("continue")
            elseif arg == "deal" then
                EncounterNegotiation.SendRequest("takeDeal")
            elseif arg == "vote" then
                EncounterNegotiation.SendRequest("vote", { choice = words[2] })
            elseif arg == "reset" then
                local doc = EncounterNegotiation.GetDoc()
                doc:BeginChange()
                doc.data.negotiation = nil
                doc:CompleteChange("Negotiation reset", { undoable = false })
                print("EotW negotiation: state cleared")
            else
                PrintState()
            end
        end,
    }
end)
