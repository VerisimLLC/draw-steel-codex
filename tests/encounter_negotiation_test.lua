--Run from the codex root with ../dependencies/lua/bin/lua.exe tests/encounter_negotiation_test.lua
--Drives the negotiation host (EncounterNegotiation.lua) through its requests
--with stand-ins for the engine, against the real book rules: the pure part of
--NegotiationRules.lua is lifted out of the file, which cannot load here whole.
--State always exists where these checks read it, and a nil is a failed test.
---@diagnostic disable: need-check-nil
local server = 1000
local documents = { data = {} }
function documents:BeginChange() end
function documents:CompleteChange() end

dmhub = {
    GetModLoading = function()
        return { GetDocumentSnapshot = function() return documents end }
    end,
    Error = function(message) print(message) end,
    loginUserid = "lisa",
}
setmetatable(dmhub, { __index = function(_, key)
    if key == "serverTime" then
        return server
    end
    return nil
end })
printf = function() end
cond = cond or function(c, a, b) if c then return a else return b end end
EotwAnalytics = { Track = function() end }

dofile("DMHub Utils/UIText.lua")
dofile("EncounterOfTheWeek/EncounterText.lua")
dofile("EncounterOfTheWeek/EncounterAuthoringText.lua")
dofile("DMHub Game Rules/TestRiders.lua")
dofile("EncounterOfTheWeek/EncounterScript.lua")

local rulesFile = assert(io.open("Draw Steel V/NegotiationRules.lua", "r"))
local rulesText = rulesFile:read("a")
rulesFile:close()
local from = assert(string.find(rulesText, "NegotiationRules = rawget", 1, true))
local marker = assert(string.find(rulesText, "-- LiveNegotiation: the in-play state", 1, true))
local to = assert(string.find(string.sub(rulesText, 1, marker), "\n[^\n]*\n[^\n]*$"))
assert(load(string.sub(rulesText, from, to), "NegotiationRules"))()

local passed = 0
local function check(condition, message)
    if not condition then
        error("FAILED: " .. tostring(message), 2)
    end
    passed = passed + 1
end

local HEROES = {
    { charid = "brunna", name = "Brunna", ownerId = "lisa" },
    { charid = "ives", name = "Ives", ownerId = "lisa" },
    { charid = "sael", name = "Sael", ownerId = "david" },
    { charid = "wren", name = "Wren", ownerId = "david" },
}
local speakers = { brunna = true }
local applied = {}
local intelligenceOn, intelligenceHeld = false, 0

EncounterMontage = {
    Heroes = function() return HEROES end,
    HeroFacts = function(charid) return { charid = charid } end,
    ApplyEffects = function(effects)
        for _, effect in ipairs(effects) do
            applied[#applied + 1] = effect
        end
        return effects, {}
    end,
    RecordAlly = function() end,
    IsPresented = function() return true end,
    FeatureUnlocked = function() return intelligenceOn end,
    SpendIntelligence = function(doc, heroids, qty)
        if intelligenceHeld < qty then
            return false
        end
        intelligenceHeld = intelligenceHeld - qty
        return true, { "Brunna" }
    end,
    Present = function() end,
}
EncounterScript.RequirementMet = function(_, facts) return speakers[facts.charid] == true end
EncounterScript.EvaluateRiders = function(riders, facts)
    local allowed = true
    for _, rider in ipairs(riders) do
        if rider.effect == "allow" and not speakers[facts.charid] then
            allowed = false
        end
    end
    return { allowed = allowed }
end
EncounterNarrative = {
    Voters = function(_, heroes)
        local seen, result = {}, {}
        for _, hero in ipairs(heroes or HEROES) do
            if not seen[hero.ownerId] then
                seen[hero.ownerId] = true
                result[#result + 1] = { key = hero.ownerId, name = hero.ownerId, heroids = {} }
            end
        end
        return result
    end,
    VoterKeyForUser = function(userid) return userid end,
}

dofile("EncounterOfTheWeek/EncounterNegotiation.lua")
local N = EncounterNegotiation

local parsed = EncounterScript.Parse([==[
# Negotiation: Hask

Attitude: Suspicious
Language: Zaliac

## Motivation: Greed

## Motivation: Protection

## Pitfall: Justice

## Pitfall: Higher Authority
Start: Known

## Argument: Cut
Appeals: Greed
|Test: Presence (Persuade)
Lands: Say it again.
Falls short: Show me coin.

## Argument: Theft
Appeals: Justice
Fails: Justice is for people with walls.

## Argument: Drink
Appeals: Nothing
|Test: Presence (Flirt)
Falls short: I am working.

## Argument: Oath
Appeals: Protection
|Allow: you speak Zaliac
|Test: Intuition (Persuade)

## Offer: Yes, but
You may cross.
|+2 malice

## Offer: No, and
He bars the bridge.
|+3 malice
]==])
check(#parsed.warnings == 0, "the script is clean: " .. tostring(parsed.warnings[1]))
local beat = parsed.beats[1]
local CUT, THEFT, DRINK, OATH = beat.arguments[1], beat.arguments[2], beat.arguments[3], beat.arguments[4]

local function Tick()
    return N.HostTick({}, beat, 1)
end

local function Send(userid, kind, args)
    dmhub.loginUserid = userid
    server = server + 1
    N.SendRequest(kind, args)
    return Tick()
end

local function PassReply()
    server = server + 13
    Tick()
end

local function Argue(argument, heroid, tier, natural)
    Send("lisa", "argue", { argumentId = argument.id, heroid = heroid, noDice = true })
    local m = N.GetState()
    if m.phase == "rolling" then
        Send("lisa", "rolled", { rollSeq = m.turn.rollSeq, tier = tier, natural = natural })
    end
end

local function Fresh()
    documents.data = {}
    applied = {}
    N.Begin({}, beat, 1)
    Tick()
    return N.GetState()
end

--the start: attitude, one speaker's language bonus, a known pitfall
local m = Fresh()
check(m.phase == "choosing", "the party has arrived")
check(m.interest == 2 and m.patience == 3, "Suspicious, plus 1 patience for one speaker")
check(m.learned[beat.traits[4].id] == true and m.learned[beat.traits[1].id] == nil, "only the known trait starts learned")
speakers = { brunna = true, ives = true, sael = true, wren = true }
check(Fresh().patience == 4, "three or more speakers add 2")
speakers = {}
check(Fresh().patience == 2, "no speakers, no bonus")
speakers = { brunna = true }
beat.language = "Caelian"
speakers = { brunna = true, ives = true, sael = true }
check(Fresh().patience == 2, "Caelian never counts")
beat.language = "Zaliac"
speakers = { brunna = true }

--something uncovered earlier starts learned
beat.traits[1].start = "unlock"
beat.traits[1].unlock = "the ledger"
documents.data = {}
applied = {}
documents.data.negotiationClues = { [EncounterScript.MatchKey("The Ledger")] = true }
N.Begin({}, beat, 1)
check(N.GetState().learned[beat.traits[1].id] == true, "an uncovered clue starts learned")
beat.traits[1].start = "hidden"

--Intelligence buys a hint, motivations first, before the first argument only
m = Fresh()
Send("lisa", "spendClue")
check(N.GetState().learned[beat.traits[1].id] == nil, "no hint until Intelligence is unlocked")
intelligenceOn, intelligenceHeld = true, 1
Send("lisa", "spendClue")
m = N.GetState()
check(m.learned[beat.traits[1].id] == true and intelligenceHeld == 0, "a hint reveals a motivation for its cost")
Send("lisa", "spendClue")
check(N.GetState().learned[beat.traits[2].id] == nil, "no hint without the Intelligence")
intelligenceHeld = 1
Argue(DRINK, "brunna", 2)
PassReply()
Send("lisa", "spendClue")
check(intelligenceHeld == 1, "no hint once the talking has started")
intelligenceOn, intelligenceHeld = false, 0

--an appeal: tier 2 raises interest, costs patience, reveals the motivation
m = Fresh()
Argue(CUT, "brunna", 2)
m = N.GetState()
check(m.phase == "reply" and m.interest == 3 and m.patience == 2, "a tier 2 appeal")
check(m.learned[beat.traits[1].id] == true, "an appeal reveals its motivation")
check(m.last.reply == "Say it again.", "the author's reply: " .. tostring(m.last.reply))
check(m.spoke.brunna == 1, "the hero has spoken")
PassReply()
check(N.GetState().phase == "choosing", "back to the table after the reply")

--a motivation works once
Argue(CUT, "ives", 3)
m = N.GetState()
check(m.interest == 3 and m.patience == 1, "a repeated appeal costs patience only")

--a pitfall needs no roll
m = Fresh()
Argue(THEFT, "brunna")
m = N.GetState()
check(m.interest == 1 and m.patience == 2 and m.last.track == "pitfall", "a pitfall fails whatever is rolled")
check(m.last.reply == "Justice is for people with walls.", "the pitfall's reply")
check(m.learned[beat.traits[3].id] == true, "a pitfall is learned the hard way")

--a neutral argument: a natural 19-20 keeps patience, a repeat is tier 1
m = Fresh()
Argue(DRINK, "brunna", 3, 19)
m = N.GetState()
check(m.interest == 3 and m.patience == 3, "a natural 19 keeps patience")
PassReply()
Argue(DRINK, "ives", 3)
m = N.GetState()
check(m.interest == 2 and m.patience == 2, "a repeated neutral is tier 1, whatever is rolled")

--a secret argument is refused to a hero who does not qualify
m = Fresh()
Send("lisa", "argue", { argumentId = OATH.id, heroid = "ives", noDice = true })
check(N.GetState().phase == "choosing", "a secret argument is refused")
Send("lisa", "argue", { argumentId = OATH.id, heroid = "brunna", noDice = true })
check(N.GetState().phase == "rolling", "and allowed to the hero who has the knack")

--another player's hero cannot be used
m = Fresh()
Send("lisa", "argue", { argumentId = CUT.id, heroid = "sael", noDice = true })
check(N.GetState().phase == "choosing", "a player cannot argue with someone else's hero")

--a stale roll does nothing, and a cancelled roll goes back to the table
m = Fresh()
Send("lisa", "argue", { argumentId = CUT.id, heroid = "brunna", noDice = true })
Send("lisa", "rolled", { rollSeq = -1, tier = 3 })
check(N.GetState().phase == "rolling", "a stale roll is ignored")
Send("lisa", "rollCancelled", { rollSeq = N.GetState().turn.rollSeq })
check(N.GetState().phase == "choosing" and N.GetState().interest == 2, "a cancelled roll changes nothing")

--reading: tier 3 finds what was asked for, and not twice before an argument
m = Fresh()
Send("lisa", "read", { heroid = "ives", noDice = true, wants = "pitfall" })
Send("lisa", "rolled", { rollSeq = N.GetState().turn.rollSeq, tier = 3 })
m = N.GetState()
check(m.learned[beat.traits[3].id] == true and m.last.found == beat.traits[3].id, "a tier 3 read finds the kind asked for")
check(m.patience == 3 and m.canRead == false, "and costs nothing")
PassReply()
Send("lisa", "read", { heroid = "ives", noDice = true })
check(N.GetState().phase == "choosing", "no second read before an argument")
Argue(DRINK, "brunna", 2)
PassReply()
check(N.GetState().canRead == true, "an argument allows another read")
Send("lisa", "read", { heroid = "ives", noDice = true })
Send("lisa", "rolled", { rollSeq = N.GetState().turn.rollSeq, tier = 1 })
check(N.GetState().patience == 1, "a tier 1 read costs patience")

--taking the deal: every player answers
m = Fresh()
Argue(CUT, "brunna", 3)
PassReply()
check(N.GetState().interest == 3, "interest 3")
Send("lisa", "takeDeal")
m = N.GetState()
check(m.phase == "voting" and m.votes.lisa.choice == "deal", "proposing is a vote")
Send("david", "vote", { choice = "deal" })
m = N.GetState()
check(m.phase == "done" and m.result.outcome == "deal", "an agreed deal stands")
check(#applied == 1 and applied[1].kind == "malice", "the offer's rules apply")
server = server + 7
check(Tick() == "done", "the beat ends after its linger")

--patience 0 is a final offer, and refusing it applies nothing
m = Fresh()
Argue(CUT, "brunna", 1)
PassReply()
Argue(CUT, "ives", 1)
PassReply()
Argue(DRINK, "ives", 2)
m = N.GetState()
check(m.patience == 0 and m.afterReply == "final", "patience 0 ends the talking")
PassReply()
check(N.GetState().phase == "final", "a final offer")
Send("lisa", "vote", { choice = "refuse" })
Send("david", "vote", { choice = "refuse" })
m = N.GetState()
check(m.result.outcome == "refused" and #applied == 0, "a refused offer applies nothing")

--a split vote says whose word settled it, on the next screen everyone sees
m = Fresh()
Argue(CUT, "brunna", 3)
PassReply()
Send("lisa", "takeDeal")
Send("david", "vote", { choice = "talk" })
m = N.GetState()
check(m.phase == "choosing" or m.phase == "done", "a split settles")
check(m.split ~= nil and (m.split == "lisa" or m.split == "david"), "a split names the player who settled it")

--who a vote is waiting for
m = Fresh()
Argue(CUT, "brunna", 3)
PassReply()
Send("lisa", "takeDeal")
local waiting = N.PendingVoters(N.GetState())
check(#waiting == 1 and waiting[1] == "david", "the vote is waiting for david")

--a player leaves during a vote: the host takes their heroes, and the vote
--needs nobody else
HEROES[3].ownerId, HEROES[4].ownerId = "lisa", "lisa"
server = server + 1
Tick()
m = N.GetState()
check(m.phase == "done" and m.result.outcome == "deal", "a vote settles when its last voter leaves")
HEROES[3].ownerId, HEROES[4].ownerId = "david", "david"

--a player leaves with the dice out: the roll passes to the hero's new
--controller, and the leaver's answer no longer counts
dmhub.GetCharacterById = function(charid)
    for _, hero in ipairs(HEROES) do
        if hero.charid == charid then
            return { ownerId = hero.ownerId }
        end
    end
end
m = Fresh()
Send("david", "argue", { argumentId = CUT.id, heroid = "sael" })
m = N.GetState()
check(m.phase == "rolling" and m.turn.userid == "david", "david rolls")
check(N.SyncTurnToOwners({ david = true }) == false, "the roll stays while the hero does")
HEROES[3].ownerId, HEROES[4].ownerId = "lisa", "lisa"
check(N.SyncTurnToOwners({}) == false, "a roll out stays with a player who is still here")
check(N.SyncTurnToOwners({ david = true }) == true, "the roll follows the hero")
m = N.GetState()
check(m.turn.userid == "lisa", "lisa rolls it now")
local rollSeq = m.turn.rollSeq
Send("david", "rolled", { rollSeq = rollSeq, tier = 3 })
check(N.GetState().phase == "rolling", "the leaver's roll is ignored")
Send("lisa", "rolled", { rollSeq = rollSeq, tier = 2 })
check(N.GetState().phase == "reply", "the new controller's roll resolves it")
HEROES[3].ownerId, HEROES[4].ownerId = "david", "david"

--a rehearsal plays the same, and its deal applies nothing
documents.data = {}
applied = {}
N.Begin({}, beat, 1, true)
Tick()
Argue(CUT, "brunna", 3)
PassReply()
Send("lisa", "takeDeal")
Send("david", "vote", { choice = "deal" })
m = N.GetState()
check(m.result.outcome == "deal" and #applied == 0, "a rehearsed deal applies nothing")

--interest 0 ends it with the "No, and"
m = Fresh()
Argue(THEFT, "brunna")
PassReply()
Argue(DRINK, "brunna", 1)
m = N.GetState()
check(m.interest == 0 and m.afterReply == "nodeal", "interest 0 is no deal")
PassReply()
m = N.GetState()
check(m.result.outcome == "nodeal" and #applied == 1, "the No, and applies")

print(string.format("encounter_negotiation_test: %d checks passed", passed))
