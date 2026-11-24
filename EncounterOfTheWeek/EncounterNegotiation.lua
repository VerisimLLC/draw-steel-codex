--Encounter of the Week: the negotiation beat.
--
--Runs a "# Negotiation: <NPC>" beat of the map's script (EncounterScript.lua)
--with no Director. The rules -- arguments, reads, votes, the book's numbers --
--are the shared negotiation session (Draw Steel V/NegotiationScene.lua), which
--the town of Blackbottom plays too. This file is its EotW HOST: where the
--state lives, who the heroes and voters are, riders, the language bonus,
--Intelligence hints, the montage roll dialog and what a deal applies. The
--screen is NegotiationSceneStage, mounted by EncounterMontageStage.lua.
--
--Design: NEGOTIATION_SCRIPTED_PLAN.md in the dmhub repo.
--
--Authority model is the montage's: the HOST is the single writer of
--negotiation.* state, from the map script's host tick. Players only stamp
--negotiation.requests[userid] and the host validates them in order. The
--acting player's client rolls (ClientTick) and reports the tier as a request.
--
--The shared document is the montage's ("eotwscript"), under its own key:
--data.negotiation is the session's state (its fields are listed at the top of
--NegotiationScene.lua), plus beatIndex, the script beat it belongs to.
--A hint bought with Intelligence leaves last = { kind = "clue", found }.

local mod = dmhub.GetModLoading()

local T = UIText.T

EncounterNegotiation = rawget(_G, "EncounterNegotiation") or {}

local DOC_ID = "eotwscript"

--what a hint costs, before the first argument (see SpendClue).
local CLUE_COST = 1

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

function EncounterNegotiation.Argument(beat, id)
    return NegotiationScene.Argument(beat, id)
end

function EncounterNegotiation.Trait(beat, id)
    return NegotiationScene.Trait(beat, id)
end

--- the host -------------------------------------------------------------------

--The document a Mutate is changing, so the host hooks that run inside one
--(a deal's effects, an Intelligence hint) write to that same change.
local m_changingDoc = nil

local function UserControlsHero(userid, hero)
    return hero ~= nil and (hero.ownerId == userid or hero.ownerId == "PARTY")
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

--What a deal does: a refused offer applies nothing; a deal, or the
--"No, and..." of interest 0, applies its offer's rules.
local function Finish(m, outcome, offer, beat)
    if outcome == "refused" or outcome == "left" or offer == nil then
        return {}
    end
    local doc = m_changingDoc or EncounterNegotiation.GetDoc()
    local heroes = EncounterMontage.Heroes()
    local anchor = heroes[1]
    local applied, newAllies = EncounterMontage.ApplyEffects(PartyScoped(offer.effects), {
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
    return applied
end

--Spend the player's Intelligence on what the party found out on the way here.
--The session has already checked CanSpendClue.
local function SpendClue(m, userid, beat, heroes)
    local doc = m_changingDoc or EncounterNegotiation.GetDoc()
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
    local trait = NegotiationScene.NextHiddenTrait(m, beat)
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
    m.seq = (tonumber(m.seq) or 0) + 1
    return string.format("Intelligence revealed %s", trait.name)
end

--The acting player's test: the same dialog as a montage test, with the
--argument's skills and the hero's edges.
local function ShowRoll(args)
    local heroToken = dmhub.GetCharacterById(args.heroid)
    if heroToken == nil or not heroToken.valid then
        args.onNotShown()
        return
    end
    local parts = EncounterMontage.BuildTestRoll(heroToken, args.attr, args.name, args.verdict)
    EncounterMontage.ShowTestRoll{
        creature = heroToken.properties,
        heroToken = heroToken,
        title = parts.title,
        rollType = parts.rollType,
        roll = parts.roll,
        modifiers = parts.modifiers,
        tiers = args.tiers,
        rollSeq = args.rollSeq,
        completeKind = "rolled",
        cancelKind = "rollCancelled",
        stillWanted = args.stillWanted,
        send = args.send,
        onNotShown = args.onNotShown,
    }
end

local function Host()
    return {
        Load = EncounterNegotiation.GetState,
        Mutate = function(description, fn)
            local doc = EncounterNegotiation.GetDoc()
            if type(doc.data.negotiation) ~= "table" then
                return
            end
            doc:BeginChange()
            m_changingDoc = doc
            local ok, err = pcall(fn, doc.data.negotiation)
            m_changingDoc = nil
            doc:CompleteChange(description, { undoable = false })
            if not ok then
                error(err)
            end
        end,
        Replace = function(m, description)
            local doc = EncounterNegotiation.GetDoc()
            doc:BeginChange()
            doc.data.negotiation = m
            if m ~= nil then
                doc.data.stageDismissAt = nil
            end
            doc:CompleteChange(description, { undoable = false })
        end,
        Beat = function()
            return (EncounterNegotiation.CurrentBeat())
        end,
        Heroes = function()
            return EncounterMontage.Heroes()
        end,
        --one vote per player; party-owned heroes share one voter.
        Voters = function(heroes)
            return EncounterNarrative.Voters(nil, heroes)
        end,
        VoterKey = function(userid, heroes)
            return EncounterNarrative.VoterKeyForUser(userid, heroes)
        end,
        MayAct = function(userid, heroes)
            return not EncounterNarrative.IsObserver(userid, heroes)
        end,
        --an argument's riders: its edges, and whether a secret one is theirs.
        Verdict = function(charid, argument)
            return EncounterScript.EvaluateRiders(argument.riders, EncounterMontage.HeroFacts(charid))
        end,
        Speaks = function(charid, language)
            local requirement = EncounterScript.ParseRequirement("you speak " .. language)
            return EncounterScript.RequirementMet(requirement, EncounterMontage.HeroFacts(charid)) and true or false
        end,
        Finish = Finish,
        --before the first argument only (the session checks that): this is
        --the book's research ahead of the talk, not a way out of a bad one.
        CanSpendClue = function(m, beat)
            return EncounterMontage.FeatureUnlocked("intelligence") and NegotiationScene.NextHiddenTrait(m, beat) ~= nil
        end,
        SpendClue = SpendClue,
        ShowRoll = ShowRoll,
        Track = function(event, fields)
            EotwAnalytics.Track("eotw_" .. event, fields)
        end,
        --there is no Leave here: the party refuses the final offer instead.
        noWalkOut = true,
    }
end

--The one session for this client, made on first use so the load order of the
--two mods does not matter.
local m_session = nil

---@return NegotiationSceneSession
function EncounterNegotiation.Session()
    if m_session == nil then
        m_session = NegotiationScene.Session(Host())
    end
    return m_session
end

--- facts ---------------------------------------------------------------------

function EncounterNegotiation.Verdict(charid, argument)
    return EncounterNegotiation.Session():Verdict(charid, argument)
end

function EncounterNegotiation.CanMakeArgument(charid, argument)
    return EncounterNegotiation.Session():CanMakeArgument(charid, argument)
end

function EncounterNegotiation.NextHiddenTrait(m, beat)
    return NegotiationScene.NextHiddenTrait(m, beat)
end

function EncounterNegotiation.CanSpendClue(m, beat)
    return EncounterNegotiation.Session():CanSpendClue(m, beat)
end

--The players a vote is still waiting for, as display names.
function EncounterNegotiation.PendingVoters(m)
    return EncounterNegotiation.Session():PendingVoters(m)
end

--- requests (player side) ---------------------------------------------------

--Stamp a request for the host: {seq, kind, ...args}. One slot per user.
function EncounterNegotiation.SendRequest(kind, args)
    return EncounterNegotiation.Session():SendRequest(kind, args)
end

--- host: the beat -------------------------------------------------------------

--Host only. Heroes changed hands: a roll out stays with its roller unless that
--player is in `away`, and the hero's new controller then rolls it afresh (as
--EncounterMontage.SyncTurnToOwners). Returns true when the turn changed.
function EncounterNegotiation.SyncTurnToOwners(away)
    return EncounterNegotiation.Session():SyncTurnToOwners(away, function(charid)
        local tok = dmhub.GetCharacterById(charid)
        return tok ~= nil and tok.ownerId or nil
    end)
end

--Seed the state for a negotiation beat. The beat opens in "arriving": nobody
--can act until the host tick, which runs once every player is in. A rehearsal
--plays the same but its deal applies nothing.
function EncounterNegotiation.Begin(script, beat, beatIndex, rehearsal)
    local doc = EncounterNegotiation.GetDoc()
    EncounterNegotiation.Session():Begin{
        beat = beat,
        rehearsal = rehearsal,
        clues = doc.data.negotiationClues or {},
        extra = { beatIndex = beatIndex },
    }
    EncounterMontage.Present(beatIndex)
end

--Run the negotiation beat from the host tick. Returns "running" while it plays
--and "done" once it is over.
function EncounterNegotiation.HostTick(script, beat, beatIndex)
    local m = EncounterNegotiation.GetState()
    if m == nil or m.beatIndex ~= beatIndex then
        EncounterNegotiation.Begin(script, beat, beatIndex)
        return "running"
    end
    if not EncounterMontage.IsPresented() then
        EncounterMontage.Present(beatIndex)
    end
    return EncounterNegotiation.Session():Tick(beat) or "running"
end

--- client: the roll -----------------------------------------------------------

function EncounterNegotiation.ClientTick()
    EncounterNegotiation.Session():ClientTick()
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

## Argument: Slide a heavy purse across the table
Appeals: Greed
PC: Call it a down payment on a friendship.
|Allow: your Wealth is 1 or higher
|Test: Presence (Persuade)
Lands: Now you are speaking my language.
Falls short: That is a start. It is not the toll.

## Argument: Let him hear who he is dealing with
Appeals: Nothing
PC: You have heard of us. Then you know what we can do for a man in your position.
|Allow: your Renown is 1 or higher
|Test: Presence (Brag)
Lands: Heard of you? Aye. All right, I am listening.
Falls short: Names do not pay tolls.
Backfires: Heroes. Wonderful. The last ones cost me a cart.

## Argument: Swear on the old road
Appeals: Protection
PC: By the old road and the ones who walked it, your people come to no harm through us.
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
