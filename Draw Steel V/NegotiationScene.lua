local mod = dmhub.GetModLoading()

--Negotiation scenes: a "# Negotiation: <NPC>" scene played with no Director.
--Heroes pick authored arguments, each secretly tagged to a motivation, a
--pitfall or nothing, and NegotiationRules applies the book's rules.
--
--This is Lisa's Encounter of the Week negotiation -- the runtime in
--EncounterOfTheWeek/EncounterNegotiation.lua, the negotiation part of
--EncounterScript.lua's parser and the negotiation stage in
--EncounterMontageStage.lua -- brought into the core codex so a place outside
--an EotW game can play one. The town of Blackbottom is the first: the Great
--Forge's Giddlebrick Thundlestrom (Codex Titlescreen/EotwForge.lua); the EotW
--game's negotiation beat (EncounterOfTheWeek/EncounterNegotiation.lua) is the
--other host, keeping its state in a shared game document.
--
--Everything that ties a scene to where it is played -- where its state lives,
--who the heroes are, how a test is rolled, what a deal does -- is a HOST
--table the caller passes to NegotiationScene.Session (documented there).
--The stage is NegotiationSceneStage.lua; its words are NegotiationSceneText.lua.
--
--The script is the markdown an EotW author writes for a negotiation beat
--(see the EotW authoring guide), minus what needs an EotW game: rules lines
--under an offer are reported and ignored, since the host decides what a deal
--does. Knack riders ("|Allow:", "|Edge:", ...) are read here; a host
--plays them by giving the session a Verdict.
--
--The state (m), as the host keeps it:
--  { phase = "arriving"|"choosing"|"rolling"|"reply"|"voting"|"final"|"done",
--    seq, interest, patience, startPatience,
--    learned = { [traitId] = true }, usedTraits = {...}, usedArguments = {...},
--    spoke = { [charid] = n }, canRead,
--    turn = nil | { kind = "argue"|"read", argumentId, heroid, heroName, userid, rollSeq, noDice, wants },
--    last = nil | { kind, argumentId, heroid, heroName, tier, total, track, reply, interest, patience, found },
--    replyAt, afterReply, votes, voteOptions, split,
--    result = nil | { outcome = "deal"|"refused"|"nodeal", interest, applied },
--    requests = { [userid] = { seq, kind, ... } }, handled = { [userid] = seq },
--    log = { { heroName, text, track, tier }, ... }, startedAt, doneAt }

NegotiationScene = rawget(_G, "NegotiationScene") or {}

local T = UIText.T
local lower = string.lower

local function trim(s)
    s = string.gsub(s or "", "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

--- the script ----------------------------------------------------------------

--The six offers, indexed by interest + 1 like NegotiationRules.offerLabels.
NegotiationScene.OFFERS = { "no, and", "no", "no, but", "yes, but", "yes", "yes, and" }
NegotiationScene.ATTITUDES = {
    hostile = true, suspicious = true, neutral = true, open = true, friendly = true, trusting = true,
}
local PRONOUNS = { he = true, she = true, they = true, it = true }
local CHARACTERISTIC_WORDS = { might = true, agility = true, reason = true, intuition = true, presence = true }

--A stable id fragment from a name: lowercase, runs of non-alphanumerics
--become single dashes (as EncounterScript's).
local function Slug(name)
    local s = lower(trim(name))
    s = string.gsub(s, "[^%w]+", "-")
    s = string.gsub(s, "^%-+", "")
    s = string.gsub(s, "%-+$", "")
    return s
end

--The key a name is matched by: lower-cased, whitespace collapsed, a leading
--"the " and trailing punctuation dropped (as EncounterScript.MatchKey).
function NegotiationScene.MatchKey(name)
    local key = lower(trim(name or ""))
    key = string.gsub(key, "%s+", " ")
    key = string.gsub(key, "^the ", "")
    key = string.gsub(key, "[%.,;:!%?]+$", "")
    return trim(key)
end

--Is "|Name: <attr>" a test? Its attr has to name a characteristic.
local function IsTestAttr(attr)
    local bare = lower(trim(string.gsub(attr or "", "%s*%b()", "")))
    for word in string.gmatch(bare, "%a+") do
        if CHARACTERISTIC_WORDS[word] then
            return true
        end
    end
    return false
end

local function NewBeat(name, line)
    return {
        kind = "negotiation",
        line = line,
        name = name,
        intro = "",
        playedBy = "",
        pronouns = "they",
        attitude = "suspicious",
        language = "",
        impression = 1,
        renown = "unknown",
        want = "",
        opening = "",
        traits = {},
        arguments = {},
        offers = {},
    }
end

--Interest (0..5) of an "## Offer:" heading, or nil.
local function OfferInterest(title)
    local key = lower(trim(string.gsub(title, "%.+%s*$", "")))
    key = string.gsub(key, "%s+", " ")
    key = string.gsub(key, "(%a) but$", "%1, but")
    key = string.gsub(key, "(%a) and$", "%1, and")
    for i, name in ipairs(NegotiationScene.OFFERS) do
        if name == key then
            return i - 1
        end
    end
    return nil
end

local function StartSection(beat, title, line, warn)
    local kind, name = string.match(title, "^([%a]+):%s*(.+)$")
    kind = kind ~= nil and lower(kind) or nil
    name = name ~= nil and trim(name) or nil
    if kind == "motivation" or kind == "pitfall" then
        local trait = { kind = kind, name = name, line = line, clue = "", start = "hidden",
            id = string.format("t%d-%s", #beat.traits + 1, Slug(name)) }
        beat.traits[#beat.traits + 1] = trait
        return trait
    elseif kind == "argument" then
        local argument = { name = name, line = line, kind = "neutral", say = "", lands = "", fallsShort = "",
            backfires = "", riders = {}, id = string.format("a%d-%s", #beat.arguments + 1, Slug(name)) }
        beat.arguments[#beat.arguments + 1] = argument
        return argument
    elseif kind == "offer" then
        local interest = OfferInterest(name)
        if interest == nil then
            warn(line, "unknown offer '%s'", tostring(name))
            return nil
        end
        local offer = { interest = interest, name = name, line = line, text = "", effects = {} }
        if beat.offers[interest + 1] ~= nil then
            warn(line, "a second offer for '%s'", tostring(name))
        else
            beat.offers[interest + 1] = offer
        end
        return offer
    end
    warn(line, "unknown heading '%s'", title)
    return nil
end

local function ReadBeatField(beat, label, rest, line, warn)
    if label == "played by" then
        beat.playedBy = rest
    elseif label == "pronouns" then
        if PRONOUNS[lower(rest)] then
            beat.pronouns = lower(rest)
        else
            warn(line, "unknown pronouns '%s'", rest)
        end
    elseif label == "attitude" then
        if NegotiationScene.ATTITUDES[lower(rest)] then
            beat.attitude = lower(rest)
        else
            warn(line, "unknown attitude '%s'", rest)
        end
    elseif label == "language" then
        beat.language = rest
    elseif label == "impression" then
        local n = tonumber(rest)
        if n ~= nil and n >= 1 and n == math.floor(n) then
            beat.impression = n
        else
            warn(line, "impression must be a whole number, not '%s'", rest)
        end
    elseif label == "renown" then
        beat.renown = lower(rest)
    elseif label == "want" then
        beat.want = rest
    elseif label == "opening" then
        beat.opening = rest
    else
        return false
    end
    return true
end

local function ReadTraitField(trait, label, rest, line, warn)
    if label == "clue" then
        trait.clue = rest
    elseif label == "start" then
        local unlock = string.match(rest, "^[Uu]nlocked by%s+(.+)$")
        if lower(rest) == "hidden" or lower(rest) == "known" then
            trait.start = lower(rest)
        elseif unlock ~= nil then
            trait.start = "unlock"
            trait.unlock = trim(unlock)
        else
            warn(line, "unknown start '%s'", rest)
        end
    else
        return false
    end
    return true
end

local function ReadArgumentField(argument, label, rest)
    if label == "appeals" then
        argument.appeals = rest
    elseif label == "pc" then
        argument.say = rest
    elseif label == "lands" then
        argument.lands = rest
    elseif label == "falls short" then
        argument.fallsShort = rest
    elseif label == "backfires" or label == "fails" then
        argument.backfires = rest
    else
        return false
    end
    return true
end

--One line of text under a heading (or above the first "##").
local function ReadLine(beat, target, l, index, warn)
    local label, rest = string.match(l, "^([%a][%a ]*):%s*(.*)$")
    local key = label ~= nil and lower(trim(label)) or nil
    local read = false
    if target == nil then
        read = key ~= nil and ReadBeatField(beat, key, trim(rest), index, warn)
        if not read then
            beat.intro = cond(beat.intro == "", l, beat.intro .. "\n" .. l)
            read = true
        end
    elseif target.interest ~= nil then
        target.text = cond(target.text == "", l, target.text .. "\n" .. l)
        read = true
    elseif target.kind == "motivation" or target.kind == "pitfall" then
        read = key ~= nil and ReadTraitField(target, key, trim(rest), index, warn)
    else
        read = key ~= nil and ReadArgumentField(target, key, trim(rest))
    end
    if not read then
        warn(index, "a line this negotiation does not understand: %s", l)
    end
end

--A "|" line: an argument's test, a knack rider ("|Allow:", "|Edge:", ... read
--by TestRiders, as in a montage). Offer rules need an EotW game.
local function ReadRuleLine(target, line, index, warn)
    local body = trim(string.gsub(string.match(line, "^|(.*)$") or "", "|%s*$", ""))
    if target ~= nil and target.interest ~= nil then
        if body ~= "" then
            warn(index, "rules under an offer are not played here (the host decides what a deal does): %s", body)
        end
        return
    end
    if target == nil or target.riders == nil then
        warn(index, "a rule outside an argument: %s", body)
        return
    end
    local riders = rawget(_G, "TestRiders")
    local effect, requirementText, round = nil, nil, nil
    if riders ~= nil then
        effect, requirementText, round = riders.ParseRiderLine(line)
    end
    if effect ~= nil then
        if requirementText == "" then
            warn(index, "a rider with no requirement: %s", body)
            return
        end
        local requirement = riders.ParseRequirement(requirementText)
        for _, problem in ipairs(riders.RequirementProblems(requirement)) do
            warn(index, "%s", problem)
        end
        target.riders[#target.riders + 1] = { effect = effect, text = requirementText, requirement = requirement, round = round, line = index }
        return
    end
    local name, attr = string.match(body, "^([^|:]+):%s*([^|]+)$")
    if name ~= nil and IsTestAttr(attr) then
        target.roll = { name = trim(name), attr = trim(attr), line = index }
        return
    end
    warn(index, "only an argument's test is played here, not: %s", body)
end

--Ties each argument to its trait once the whole script has been read.
local function Finish(beat, warn)
    if beat.name == "" then
        warn(beat.line, "the negotiation has no NPC name")
    end
    if #beat.arguments == 0 then
        warn(beat.line, "%s has no arguments", beat.name)
    end
    local byKey = {}
    for _, trait in ipairs(beat.traits) do
        byKey[NegotiationScene.MatchKey(trait.name)] = trait
    end
    for _, argument in ipairs(beat.arguments) do
        local appeals = argument.appeals
        if appeals == nil or appeals == "" then
            warn(argument.line, "'%s' does not say what it appeals to", argument.name)
        elseif lower(appeals) ~= "nothing" and lower(appeals) ~= "neutral" then
            local trait = byKey[NegotiationScene.MatchKey(appeals)]
            if trait == nil then
                warn(argument.line, "'%s' appeals to '%s', which is not a motivation or pitfall here", argument.name, appeals)
            else
                argument.kind = trait.kind
                argument.traitId = trait.id
            end
        end
        if argument.roll == nil and argument.kind ~= "pitfall" then
            warn(argument.line, "'%s' has no test", argument.name)
        end
    end
    for i, name in ipairs(NegotiationScene.OFFERS) do
        if beat.offers[i] == nil then
            warn(beat.line, "no '%s' offer", name)
        end
    end
end

--Parse one negotiation script. Returns the beat (the shape EncounterScript
--gives a negotiation beat, so the same stage reads both) and its warnings
--("line N: ..."). The beat is nil when there is no "# Negotiation:" heading.
---@param text string
---@return table|nil beat
---@return string[] warnings
function NegotiationScene.Parse(text)
    local warnings = {}
    local function warn(line, fmt, ...)
        warnings[#warnings + 1] = string.format("line %s: " .. fmt, tostring(line), ...)
    end
    local beat = nil
    local target = nil
    local index = 0
    for raw in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
        index = index + 1
        local l = trim(string.gsub(raw, "\r", ""))
        if l ~= "" then
            local npc = string.match(l, "^#%s+[Nn]egotiation:%s*(.+)$")
            local section = string.match(l, "^##%s+(.+)$")
            if npc ~= nil then
                if beat ~= nil then
                    warn(index, "a second negotiation in one script")
                else
                    beat = NewBeat(trim(npc), index)
                    target = nil
                end
            elseif beat == nil then
                warn(index, "text before the '# Negotiation:' heading")
            elseif section ~= nil then
                target = StartSection(beat, trim(section), index, warn)
            elseif string.sub(l, 1, 1) == "|" then
                ReadRuleLine(target, l, index, warn)
            elseif string.sub(l, 1, 1) == "#" then
                warn(index, "unknown heading '%s'", l)
            else
                ReadLine(beat, target, l, index, warn)
            end
        end
    end
    if beat ~= nil then
        Finish(beat, warn)
    else
        warnings[#warnings + 1] = "no '# Negotiation: <name>' heading"
    end
    return beat, warnings
end

--"Presence (Persuade, Flirt)" -> the characteristics it names (attrid ->
--true) and the skills it names ({ {id, name}, ... }), by the same substring
--rule as EncounterScript.ParseAttr.
---@param attr string
---@return table<string, boolean> characteristics
---@return {id: string, name: string}[] skills
function NegotiationScene.ParseTest(attr)
    local text = lower(attr or "")
    local characteristics = {}
    for attrid, info in pairs(creature.attributesInfo or {}) do
        local desc = info.description
        if type(desc) == "string" and desc ~= "" and string.find(text, lower(desc), 1, true) ~= nil then
            characteristics[attrid] = true
        end
    end
    local skills = {}
    for _, skillInfo in ipairs(Skill.skillsDropdownOptions or {}) do
        local name = skillInfo.text
        if type(name) == "string" and name ~= "" and string.find(text, lower(name), 1, true) ~= nil then
            skills[#skills + 1] = { id = skillInfo.id, name = name }
        end
    end
    return characteristics, skills
end

--The tier a test reached: a natural 19-20 is always tier 3.
function NegotiationScene.TierFor(natural, total)
    if (tonumber(natural) or 0) >= 19 then
        return 3
    end
    return NegotiationRules.TierForTotal(tonumber(total) or 0)
end

--- the session -----------------------------------------------------------------

--How long an NPC's reply stays up if nobody presses on.
local REPLY_SECONDS = 12
--And how long the finished negotiation holds before Tick reports "done".
local DONE_LINGER_SECONDS = 6
--The book's discovery test: any of the three, whichever suits the hero.
NegotiationScene.READ_ATTR = "Reason, Intuition or Presence"

--- @class NegotiationSceneSession
--- @field host table
--- @field launchedRollSeq number|nil
local Session = {}
Session.__index = Session

--A negotiation played under one host. The host (all functions; the ones
--marked optional may be left out):
--  Load() -> m | nil                   the state, as last written
--  Mutate(description, fn(m))          change the state: fn edits m in place
--  Replace(m | nil, description)       put a whole new state (start, reset)
--  Beat() -> beat | nil                the negotiation being played (Parse)
--  Heroes() -> { {charid, name, ownerId}, ... }   who may speak
--  Voters(heroes) -> { {key, name}, ... }         optional; default one per owner
--  VoterKey(userid, heroes) -> key | nil          optional; default the userid
--  Now() -> seconds                    optional; default dmhub.serverTime
--  UserId() -> userid                  optional; default dmhub.loginUserid
--  Verdict(charid, argument) -> verdict | nil     optional; an argument's riders
--  Speaks(charid, language) -> bool    optional; the book's language bonus
--  Finish(m, outcome, offer, beat) -> applied     optional; what a deal does
--  CanSpendClue(m, beat) / SpendClue(m, userid, beat, heroes)  optional; Intelligence
--  ShowRoll(args)                      the acting player's test: args = {kind, heroid,
--                                      heroName, attr, name, argument, verdict, rollSeq,
--                                      stillWanted(), send(kind, fields), onNotShown()}.
--                                      Report with send("rolled", {rollSeq, tier, total,
--                                      natural}) or send("rollCancelled", {rollSeq}).
--  Track(event, fields)                optional; analytics
--  replySeconds, doneLingerSeconds     optional numbers
--  noWalkOut                           optional; true ignores "walkOut" requests
--                                      (a host with no Leave button)
---@param host table
---@return NegotiationSceneSession
function NegotiationScene.Session(host)
    local session = setmetatable({ host = host, launchedRollSeq = nil }, Session)
    return session
end

function Session:Now()
    if self.host.Now ~= nil then
        return self.host.Now()
    end
    return dmhub.serverTime
end

function Session:UserId()
    if self.host.UserId ~= nil then
        return self.host.UserId()
    end
    return dmhub.loginUserid
end

function Session:GetState()
    local m = self.host.Load()
    if type(m) ~= "table" then
        return nil
    end
    return m
end

function Session:Beat()
    return self.host.Beat()
end

function Session:Heroes()
    return self.host.Heroes() or {}
end

local function FindById(list, id)
    for _, item in ipairs(list or {}) do
        if item.id == id then
            return item
        end
    end
    return nil
end

function NegotiationScene.Argument(beat, id)
    return FindById(beat.arguments, id)
end

function NegotiationScene.Trait(beat, id)
    return FindById(beat.traits, id)
end

--The rider verdict for a hero on an argument, or nil (no riders here).
function Session:Verdict(charid, argument)
    if self.host.Verdict == nil or #(argument.riders or {}) == 0 then
        return nil
    end
    local verdict = nil
    local ok, err = pcall(function() verdict = self.host.Verdict(charid, argument) end)
    if not ok then
        printf("Negotiation: rider verdict failed: %s", tostring(err))
    end
    return verdict
end

--May this hero make this argument? A secret one is hidden from everyone else.
function Session:CanMakeArgument(charid, argument)
    local verdict = self:Verdict(charid, argument)
    return verdict == nil or verdict.allowed ~= false
end

--The book's language rule: one speaker of the NPC's native language adds 1
--patience at the start, three or more add 2. Caelian never counts.
function Session:LanguageBonus(beat, heroes)
    if self.host.Speaks == nil or beat.language == "" or lower(beat.language) == "caelian" then
        return 0
    end
    local speakers = 0
    for _, hero in ipairs(heroes) do
        local met = false
        pcall(function() met = self.host.Speaks(hero.charid, beat.language) == true end)
        if met then
            speakers = speakers + 1
        end
    end
    if speakers >= 3 then
        return 2
    end
    return speakers >= 1 and 1 or 0
end

function Session:Voters(heroes)
    if self.host.Voters ~= nil then
        return self.host.Voters(heroes)
    end
    local voters, seen = {}, {}
    for _, hero in ipairs(heroes) do
        local key = hero.ownerId or ""
        if not seen[key] then
            seen[key] = true
            voters[#voters + 1] = { key = key, name = hero.playerName or hero.name }
        end
    end
    return voters
end

function Session:VoterKey(userid, heroes)
    if self.host.VoterKey ~= nil then
        return self.host.VoterKey(userid, heroes)
    end
    for _, voter in ipairs(self:Voters(heroes)) do
        if voter.key == userid then
            return userid
        end
    end
    return nil
end

--The players a vote is still waiting for, as display names.
function Session:PendingVoters(m)
    local pending = {}
    for _, voter in ipairs(self:Voters(self:Heroes())) do
        if (m.votes or {})[voter.key] == nil then
            pending[#pending + 1] = voter.name
        end
    end
    return pending
end

--- requests (player side) ---------------------------------------------------

--Stamp a request for the host: {seq, kind, ...args}. One slot per user; a
--newer request replaces an unhandled older one.
function Session:SendRequest(kind, args)
    local userid = self:UserId()
    if self:GetState() == nil then
        return false
    end
    local now = self:Now()
    self.host.Mutate("Negotiation request: " .. tostring(kind), function(m)
        m.requests = m.requests or {}
        local prev = m.requests[userid]
        local req = { seq = ((prev ~= nil and prev.seq) or 0) + 1, kind = kind, time = now }
        for k, v in pairs(args or {}) do
            req[k] = v
        end
        m.requests[userid] = req
    end)
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

--An argument's reply: the author's line for how it went, else a stock one.
local function ReplyFor(argument, delta, track, repeated)
    if track == "pitfall" then
        return argument.backfires ~= "" and argument.backfires or T("negscene.reply.negative")
    end
    if delta.interest > 0 then
        return argument.lands ~= "" and argument.lands or T("negscene.reply.positive")
    end
    if delta.interest < 0 then
        return argument.backfires ~= "" and argument.backfires or T("negscene.reply.negative")
    end
    if repeated then
        return T("negscene.reply.impatient")
    end
    return argument.fallsShort ~= "" and argument.fallsShort or T("negscene.reply.impatient")
end

function Session:AfterMeters(m)
    local terminal = NegotiationRules.Terminal(m.interest, m.patience)
    m.afterReply = nil
    if terminal == "nodeal" then
        m.afterReply = "nodeal"
    elseif terminal == "final" then
        m.afterReply = "final"
    end
    m.turn = nil
    m.phase = "reply"
    m.replyAt = self:Now()
    Bump(m)
end

--Apply an argument under the book's rules. A pitfall fails whatever is
--rolled, so it reaches here with no tier.
function Session:ResolveArgument(m, beat, argument, hero, tier, total, natural)
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
        heroid = hero.charid,
        heroName = hero.name,
        tier = tier,
        total = total,
        track = track,
        reply = ReplyFor(argument, delta, track, repeated),
        interest = delta.interest,
        patience = delta.patience,
    }
    m.log = m.log or {}
    --heroid / argumentId: the stage shows who made each argument on its card.
    m.log[#m.log + 1] = { heroName = hero.name, text = argument.name, track = track, tier = tier,
        heroid = hero.charid, argumentId = argument.id }
    self:AfterMeters(m)
end

--Read the NPC, under the book's discovery test: tier 1 costs patience, tier 3
--reveals one motivation or pitfall of the hero's choice of kind.
function Session:ResolveRead(m, beat, hero, tier, total, wants)
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
        heroid = hero.charid,
        heroName = hero.name,
        tier = tier,
        total = total,
        found = found ~= nil and found.id or nil,
    }
    self:AfterMeters(m)
end

--End the negotiation: outcome "deal" (the offer taken), "refused" (walked
--away from the final offer), "nodeal" (interest fell to 0) or "left" (a Leave
--button). The host's Finish decides what each one does.
function Session:Finish(m, beat, outcome)
    local offer = beat.offers[m.interest + 1]
    local applied = {}
    if self.host.Finish ~= nil and not m.rehearsal then
        local ok, result = pcall(self.host.Finish, m, outcome, offer, beat)
        if not ok then
            printf("Negotiation: the host's finish failed: %s", tostring(result))
        elseif type(result) == "table" then
            applied = result
        end
    end
    m.result = { outcome = outcome, interest = m.interest, applied = applied }
    m.turn = nil
    m.votes = nil
    m.voteOptions = nil
    m.phase = "done"
    m.doneAt = self:Now()
    Bump(m)
    printf("Negotiation: over (%s at interest %d)", tostring(outcome), m.interest)
    if self.host.Track ~= nil then
        pcall(self.host.Track, "negotiation_end", {
            npc = beat.name,
            outcome = outcome,
            interest = m.interest,
            patience = m.patience,
            arguments = #(m.log or {}),
        })
    end
end

local function OpenVote(m, phase, options)
    m.phase = phase
    m.votes = {}
    m.voteOptions = options
    Bump(m)
end

--Everyone has voted: an agreed choice stands, and a split one is settled by a
--random player, as a split narrative choice is.
function Session:SettleVote(m, beat, heroes)
    local voters = self:Voters(heroes)
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
        self:Finish(m, beat, choice == "deal" and "deal" or "refused")
    end
end

--May Intelligence buy a hint now? Only where the host has Intelligence.
function Session:CanSpendClue(m, beat)
    if self.host.CanSpendClue == nil then
        return false
    end
    return m.phase == "choosing" and #(m.log or {}) == 0 and self.host.CanSpendClue(m, beat) == true
end

--The next trait the party has not learned, motivations first.
function NegotiationScene.NextHiddenTrait(m, beat)
    for _, kind in ipairs({ "motivation", "pitfall" }) do
        for _, trait in ipairs(beat.traits) do
            if trait.kind == kind and not (m.learned or {})[trait.id] then
                return trait
            end
        end
    end
    return nil
end

function Session:HandleRequest(m, userid, req, beat, heroes)
    local kind = req.kind

    if kind == "spendClue" then
        if not self:CanSpendClue(m, beat) or self.host.SpendClue == nil then
            return nil
        end
        return self.host.SpendClue(m, userid, beat, heroes)
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
        local argument = NegotiationScene.Argument(beat, req.argumentId)
        if argument == nil then
            return string.format("no argument '%s'", tostring(req.argumentId))
        end
        if not self:CanMakeArgument(hero.charid, argument) then
            return string.format("%s may not make '%s'", hero.name, argument.name)
        end
        if argument.kind == "pitfall" then
            self:ResolveArgument(m, beat, argument, hero, nil, nil, nil)
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
            self:ResolveRead(m, beat, hero, tier, req.total, t.wants)
        else
            self:ResolveArgument(m, beat, NegotiationScene.Argument(beat, t.argumentId), hero, tier, req.total, req.natural)
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

    --walking out (a Leave button): the talk ends where it stands, with
    --outcome "left"; what that means is the host's to decide (Finish). The
    --screen closes at once rather than lingering.
    if kind == "walkOut" then
        if m.phase == "done" or self.host.noWalkOut then
            return nil
        end
        self:Finish(m, beat, "left")
        m.doneAt = 0
        return "walked out"
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
        local key = self:VoterKey(userid, heroes)
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

--- host: the scene -----------------------------------------------------------

--Seed the state. The scene opens in "arriving": nobody can act until the
--first Tick. options = { attitude = id (overrides the script's),
--rehearsal = true (a deal applies nothing), finalOptions = { "deal", ... },
--clues = { [MatchKey(label)] = true } (opens "Start: Unlocked by" traits),
--extra = { key = value } (host fields stored on the state, e.g. a beat index),
--beat = the beat to seed from (default host.Beat(), which may read the state) }.
function Session:Begin(options)
    options = options or {}
    local beat = options.beat or self:Beat()
    if beat == nil then
        return false
    end
    local attitude = NegotiationRules.AttitudeById(options.attitude or beat.attitude)
    local heroes = self:Heroes()
    local patience = math.min(NegotiationRules.MAX, attitude.patience + self:LanguageBonus(beat, heroes))
    local learned = {}
    for _, trait in ipairs(beat.traits) do
        if trait.start == "known" or (trait.start == "unlock" and options.clues ~= nil and options.clues[NegotiationScene.MatchKey(trait.unlock)]) then
            learned[trait.id] = true
        end
    end
    local now = self:Now()
    local state = {
        phase = "arriving",
        rehearsal = options.rehearsal,
        finalOptions = options.finalOptions,
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
        startedAt = now,
        seq = 0,
    }
    for k, v in pairs(options.extra or {}) do
        state[k] = v
    end
    self.host.Replace(state, "Negotiation started")
    printf("Negotiation: started with %s (interest %d, patience %d)", tostring(beat.name), attitude.interest, patience)
    return true
end

--Run the scene one step: handle requests in order, settle votes, move on
--from a reply. Returns "running" while it plays, "done" once it is over
--and has lingered, nil when there is no scene. `beat` (optional) is the beat
--being played, when the caller already has it; the default is host.Beat().
---@param beat table|nil
---@return string|nil
function Session:Tick(beat)
    local m = self:GetState()
    beat = beat or self:Beat()
    if m == nil or beat == nil then
        return nil
    end
    local heroes = self:Heroes()

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

    local now = self:Now()
    local replySeconds = self.host.replySeconds or REPLY_SECONDS
    local finalOptions = m.finalOptions or { "deal", "refuse" }
    self.host.Mutate("Negotiation tick", function(state)
        if state.phase == "arriving" then
            state.phase = "choosing"
            state.startedAt = now
            Bump(state)
        end
        for _, p in ipairs(pending) do
            state.handled = state.handled or {}
            state.handled[p.userid] = p.req.seq
            local ok, result = pcall(self.HandleRequest, self, state, p.userid, p.req, beat, heroes)
            if not ok then
                printf("Negotiation: request %s from %s failed: %s", tostring(p.req.kind), tostring(p.userid), tostring(result))
            elseif result ~= nil then
                printf("Negotiation: %s", tostring(result))
            end
        end

        --every tick, not only on a vote: a player who leaves stops being a
        --voter, and that can complete the vote.
        if state.phase == "voting" or state.phase == "final" then
            self:SettleVote(state, beat, heroes)
        end

        if state.phase == "reply" then
            local age = now - (tonumber(state.replyAt) or 0)
            if age >= replySeconds then
                if state.afterReply == "nodeal" then
                    self:Finish(state, beat, "nodeal")
                elseif state.afterReply == "final" then
                    OpenVote(state, "final", finalOptions)
                else
                    state.phase = "choosing"
                    Bump(state)
                end
            end
        end
    end)

    m = self:GetState()
    if m ~= nil and m.phase == "done" then
        local age = now - (tonumber(m.doneAt) or 0)
        if age >= (self.host.doneLingerSeconds or DONE_LINGER_SECONDS) then
            return "done"
        end
    end
    return "running"
end

--Host only. Heroes changed hands: a roll out stays with its roller unless
--that player is in `away` (a set of userids), and the hero's new controller
--(ownerOf(charid) -> userid | nil) then rolls it afresh. Returns true when
--the turn changed.
---@param away table<string, boolean>|nil
---@param ownerOf fun(charid: string): string|nil
---@return boolean
function Session:SyncTurnToOwners(away, ownerOf)
    away = away or {}
    local m = self:GetState()
    if m == nil or type(m.turn) ~= "table" or not away[m.turn.userid] then
        return false
    end
    local owner = ownerOf(m.turn.heroid)
    if owner == nil or owner == "PARTY" or owner == m.turn.userid then
        return false
    end
    printf("Negotiation: %s's roll passes from %s to %s", tostring(m.turn.heroName), tostring(m.turn.userid), owner)
    self.host.Mutate("Negotiation: the roll changes hands", function(state)
        if type(state.turn) == "table" then
            state.turn.userid = owner
            Bump(state)
        end
    end)
    return true
end

--- client: the roll ------------------------------------------------------------

--The acting player's client shows the test for the turn, once per roll.
function Session:ClientTick()
    local m = self:GetState()
    if m == nil or m.turn == nil or m.phase ~= "rolling" then
        self.launchedRollSeq = nil
        return
    end
    local t = m.turn
    if t.noDice or t.userid ~= self:UserId() or self.launchedRollSeq == t.rollSeq then
        return
    end
    local beat = self:Beat()
    if beat == nil or self.host.ShowRoll == nil then
        return
    end
    self.launchedRollSeq = t.rollSeq

    local attr = NegotiationScene.READ_ATTR
    local name = T("negscene.roll.read_name")
    local verdict = nil
    local argument = nil
    if t.kind == "argue" then
        argument = NegotiationScene.Argument(beat, t.argumentId)
        if argument == nil or argument.roll == nil then
            return
        end
        attr = argument.roll.attr
        name = argument.name
        verdict = self:Verdict(t.heroid, argument)
    end
    local rollSeq = t.rollSeq
    local session = self
    self.host.ShowRoll{
        kind = t.kind,
        heroid = t.heroid,
        heroName = t.heroName,
        attr = attr,
        name = name,
        argument = argument,
        verdict = verdict,
        rollSeq = rollSeq,
        tiers = { T("negscene.roll.tier1"), T("negscene.roll.tier2"), T("negscene.roll.tier3") },
        stillWanted = function()
            local live = session:GetState()
            return live ~= nil and live.turn ~= nil and live.phase == "rolling" and live.turn.rollSeq == rollSeq
        end,
        send = function(kind, fields)
            session:SendRequest(kind, fields)
        end,
        onNotShown = function()
            session.launchedRollSeq = nil
        end,
    }
end

--- a host that keeps the state in this client only ------------------------------

--For a negotiation one player plays alone (the town): the state is a plain
--table here, and this client is host and player both. Pass the fields the
--scene needs (Beat, Heroes, ShowRoll, Finish, ...); Load / Mutate / Replace
--and Now are filled in. Call session:Tick() and session:ClientTick() from a
--think (the stage does when its args say selfHosted).
---@param host table
---@return NegotiationSceneSession
function NegotiationScene.LocalSession(host)
    local state = nil
    host.Load = function()
        return state
    end
    host.Mutate = function(description, fn)
        if state ~= nil then
            fn(state)
            state.revision = (tonumber(state.revision) or 0) + 1
        end
    end
    host.Replace = function(m, description)
        state = m
    end
    if host.Now == nil then
        host.Now = function()
            return dmhub.Time()
        end
    end
    return NegotiationScene.Session(host)
end
