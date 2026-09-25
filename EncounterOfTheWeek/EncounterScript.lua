--Encounter of the Week: the script parser.
--
--The week's journal document is a SCRIPT: an ordered list of beats, each a
--"#" heading. "# Encounter" is the combat (the [[encounter]] island, played
--exactly as before); "# Montage" is a montage played before it. Design and
--grammar: EncounterOfTheWeek.md, "Encounter scripts: montage beats before
--combat".
--
--This module is PURE Lua: no engine globals are touched at load or parse
--time, so it runs under the bundled lua.exe (tests/encounter_script_test.lua).
--Anything that needs the engine (resolving item and monster names, the
--characteristic/skill tables) is injected by the caller.
--
--Parse output:
--  {
--    beats = { beat, ... },     -- document order
--    warnings = { "line N: ...", ... },
--    hasEncounterTag = bool,    -- a [[encounter]] island anywhere in the text
--  }
--  beat = { kind = "montage"|"narrative"|"encounter"|"unknown", title, line,
--           tags = {name,...},
--           -- montage only:
--           intro = "", sceneTag = "scene"|"scene:x"|nil,
--           rounds = { { number, line, entries = { entry, ... },
--                        scaling = { scalingDirective, ... } }, ... },
--           -- narrative only:
--           intro = "", sceneTag = ..., sections = { section, ... },
--           unlocks = { { feature = "intelligence", name, line }, ... },
--           -- encounter only:
--           setup = { setupInstruction, ... } }
--  setupInstruction = { kind = "placeobjects"|"unknown", label = "Trap", line,
--                       text = "Place 4 Snare Trap objects in Trap zones and delete other Trap zones",
--                       -- placeobjects: qty = 4, object = "Snare Trap",
--                       -- zone = "trap" (lower-cased keyword name), deleteOthers = bool }
--  A "Label: Place <n> <Object> object(s) in <Zone> zone(s) [and delete
--  (the) other <Zone> zones]" paragraph under "# Encounter" is a setup
--  instruction the host runs once, right before the monsters are spawned:
--  <n> tiles are drawn at random from every <Zone> zone on the map, one
--  <Object> is placed on each, and with the delete clause every <Zone>
--  tile that was NOT drawn is removed from its zone record (a record left
--  with no tiles is deleted). Any other "Label:" paragraph there is an
--  unknown instruction (warning).
--  scalingDirective = { min = 3, max = 5 (nil = open-ended), line,
--                       removals = { opportunity = 1, threat = 1 },
--                       text = "3-5 Players: -1 Opportunity, -1 Threat" }
--  A "3-5 Players: -1 Opportunity, -1 Threat" line directly under a
--  "## Round N" heading. At that party size the round drops that many of
--  each kind, drawn at random (once, when the party has arrived) from the
--  entries THAT round introduces, skipping any marked "(Required)".
--  EncounterScript.ChooseRemovedEntries makes the draw; the montage stores
--  it and never shows or mentions what it dropped.
--  entry = { id, kind = "opportunity"|"threat", name, required, locked,
--            temporary, round, line,
--            description = "", approach = "", consequence = nil | { text, effects },
--            options = { option, ... } }
--  A heading may carry any of "(Required)", "(Locked)" and "(Temporary)",
--  alone or together ("(Required, Locked)"); the tags are stripped from
--  the name. A LOCKED entry is not on the board at all -- never shown,
--  never approachable, and a locked threat delivers no consequence --
--  until some other outcome's "Unlock <name>" clause lets it on (matched
--  by EncounterScript.MatchKey). It then appears at once if its round has
--  come, or when that round does. Locked entries are out of the
--  party-size draw, like required ones. A TEMPORARY entry does not
--  persist the way every other entry does: it is gone at the end of the
--  round it APPEARED in, and a temporary threat that was not vanquished
--  delivers its consequence there and then rather than at the end of the
--  montage.
--  option = { name, line, text = "", roll = nil | { name, attr, tiers = {...},
--             teasers = { [tierIndex] = "..." | nil },
--             effects = { [tierIndex] = { effect, ... } },
--             riders = { rider, ... } } }
--  rider = { effect = "allow"|"edge"|"doubleedge"|"bane"|"doublebane",
--            text = "You are skilled in Magic or you are an Elementalist",
--            line, requirement = { text, unrecognized = bool,
--              alternatives = { { kind = "skill"|"language"|"kindred"|"unknown",
--                                 name = "magic" (normalized), text = clause }, ... } } }
--  See "riders" below for the line grammar and EvaluateRiders for how a
--  hero's facts are weighed against them.
--  A tier line may read "teaser => full text": tiers[t] is the full text
--  (the only part the effect grammar sees) and teasers[t] is what players
--  see before the roll lands. Lines without "=>" have no teaser.
--  section = { id, name, line, text = "", prompt = "", sceneTag = nil,
--              mode = "together"|"individual", modeExplicit = bool,
--              implicitOption = bool, options = { narrativeOption, ... },
--              unlocks = { { feature = "intelligence", name, line }, ... } }
--  An "Unlock: <Feature>" line in a narrative beat turns on an optional
--  feature of the game mode (EncounterScript.FEATURES) when that section
--  arrives -- or, written above the first "##", when the beat opens. It is
--  a line of the SCENE, not of an option: a feature is not something the
--  party can choose away. Today the one feature is Intelligence.
--  narrativeOption = { name, line, text = "", implicit = bool,
--                      effects = { effect, ... } }
--  effect = { kind = "item"|"stamina"|"heal"|"temphp"|"surges"|"recovery"|
--                    "loserecovery"|"herotoken"|"intelligence"|"malice"|
--                    "ally"|"vanquish"|
--                    "initiative"|"nosurprise"|"fairinitiative"|
--                    "knowstamina"|"revealzones"|"unlock"|"testmod"|
--                    "narrative",
--             target = "self"|"party", qty = n, name = "...", text = clause,
--             key = "interrogate the goblin" (unlock: the entry key;
--               testmod: the option key), EncounterScript.MatchKey of name,
--             effect = "edge"|"doubleedge"|"bane"|"doublebane" (testmod:
--               a standing edge/bane on the "### <name>" test, for whoever
--               takes it -- unlike a "|Edge:" rider, which is weighed
--               against the acting hero's own facts),
--             hidden = true (the clause was written inside "{...}": it is
--               applied exactly as written but never shown to a player --
--               EncounterScript.VisibleText takes it out of the display),
--             outcome = "win"|"lose"|"surprise"|"surprised" (initiative only),
--             keyword = "goblin" (knowstamina only: lower-cased, singular),
--             zone = "trap" (revealzones only: lower-cased, singular keyword name),
--             unrecognized = true (narrative clauses the grammar did not match) }

EncounterScript = rawget(_G, "EncounterScript") or {}

--cond() is an engine global; give the pure module its own when it is
--missing (the interpreter and the tests).
if rawget(_G, "cond") == nil then
    cond = function(c, a, b)
        if c then
            return a
        end
        return b
    end
end

local NUMBER_WORDS = {
    a = 1, an = 1, one = 1, two = 2, three = 3, four = 4, five = 5,
    six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
}

local function trim(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function lower(s)
    return string.lower(s)
end

--"one" / "3" / "a" -> number, or nil.
function EncounterScript.ParseQuantity(word)
    if word == nil then
        return nil
    end
    word = lower(trim(word))
    local n = tonumber(word)
    if n ~= nil then
        return math.floor(n)
    end
    return NUMBER_WORDS[word]
end

--A stable id fragment from a name: lowercase, runs of non-alphanumerics
--become single dashes.
local function Slug(name)
    local s = lower(trim(name))
    s = string.gsub(s, "[^%w]+", "-")
    s = string.gsub(s, "^%-+", "")
    s = string.gsub(s, "%-+$", "")
    return s
end

--- effect clauses ---------------------------------------------------------

--The mode marker paragraph of a narrative section: "Choose together:",
--"Choose individually:", "Each hero chooses:", ... Returns "together",
--"individual", "prompt" (a bare "Options:"/"Choose:" that only carries the
--prompt text) or nil when the label is not a marker at all.
local function NarrativeMode(label)
    local lc = lower(trim(label or ""))
    if lc == "" then
        return nil
    end
    local function has(word)
        return string.find(lc, word, 1, true) ~= nil
    end
    if has("together") or has("as one") or has("as a group") or has("agree") or has("unanimous") then
        return "together"
    end
    if has("individual") or has("separately") or has("each hero") or has("each of you")
        or has("their own") or has("each player") then
        return "individual"
    end
    if lc == "options" or lc == "option" or lc == "choose" or lc == "choice" or lc == "prompt" then
        return "prompt"
    end
    return nil
end

--- feature unlocks ---------------------------------------------------------

--The optional features of Encounter of the Week a script turns on for itself,
--by writing "Unlock: <Feature>" in a narrative beat. Keyed by MatchKey, so
--"unlock: intelligence" and "Unlock: Intelligence" are the same line.
--
--A feature is off unless a script asks for it: a week that never mentions
--Intelligence never shows the pool or the Tactical Preparation screen, and
--plays exactly as it did before the feature existed.
--`explanation` is what the party is told the moment the feature arrives: a
--currency nobody has explained is a number in the corner of the screen.
EncounterScript.FEATURES = {
    intelligence = {
        key = "intelligence",
        name = "Intelligence",
        summary = "the party's shared Intelligence pool and the Tactical Preparation screen",
        explanation = "Intelligence is an important currency! When an encounter begins you will be able to spend your Intelligence gained to sway things in your favor. Try to acquire as much as you can.",
    },
}

--"Unlock: Intelligence" -> the feature record, or nil when the name is not
--one we know. The label is matched loosely ("Unlock", "Unlocks", "Unlock
--feature"), the name through MatchKey.
function EncounterScript.ParseFeatureUnlock(label, rest)
    local lc = lower(trim(label or ""))
    if lc ~= "unlock" and lc ~= "unlocks" and lc ~= "unlock feature" and lc ~= "unlocks feature" then
        return nil, nil
    end
    local name = trim(rest or "")
    if name == "" then
        return nil, ""
    end
    return EncounterScript.FEATURES[EncounterScript.MatchKey(name)], name
end

--Every feature name a script unlocks, as a set keyed by feature key.
function EncounterScript.UnlockedFeatures(parse)
    local result = {}
    for _, b in ipairs((parse and parse.beats) or {}) do
        for _, u in ipairs(b.unlocks or {}) do
            result[u.feature] = true
        end
        for _, sec in ipairs(b.sections or {}) do
            for _, u in ipairs(sec.unlocks or {}) do
                result[u.feature] = true
            end
        end
    end
    return result
end

--"{...}" marks a HIDDEN run of a tier (or Consequence:) line: everything
--inside the braces is parsed and applied exactly as if it were written
--plainly, but it is never shown to a player. The braces do not have to
--wrap a whole clause list -- "You gain a Rope. {Unlock the Old Mill}" is
--the normal shape -- and an unterminated "{" hides the rest of the line.
--Returns the brace runs as { open, close } byte indices, in order.
local function HiddenRanges(text)
    local ranges = {}
    local pos = 1
    while true do
        local open = string.find(text, "{", pos, true)
        if open == nil then
            break
        end
        local close = string.find(text, "}", open + 1, true)
        ranges[#ranges + 1] = { open = open, close = close or (#text + 1) }
        if close == nil then
            break
        end
        pos = close + 1
    end
    return ranges
end

local function InHiddenRange(ranges, i)
    for _, r in ipairs(ranges) do
        if i >= r.open and i <= r.close then
            return true
        end
    end
    return false
end

--The text a player is shown: the same line with every "{...}" run taken
--out, and the punctuation the removal stranded tidied up ("You gain a
--Rope, {Unlock the Old Mill}, and smile" -> "You gain a Rope, and smile").
--Display paths go through this (EncounterScript.TierDisplayText and
--EncounterScript.MarkupRules already do); the effect grammar goes on
--seeing the untouched line.
function EncounterScript.VisibleText(text)
    text = text or ""
    local ranges = HiddenRanges(text)
    if #ranges == 0 then
        return text
    end
    local out = {}
    local copied = 1
    for _, r in ipairs(ranges) do
        out[#out + 1] = string.sub(text, copied, r.open - 1)
        copied = r.close + 1
    end
    out[#out + 1] = string.sub(text, copied)
    local result = table.concat(out)
    result = string.gsub(result, "%s+", " ")
    result = string.gsub(result, "%s+([%.,;!%?])", "%1")
    --the removal can leave two separators back to back; collapse runs of
    --them down to the first one.
    while true do
        local collapsed, n = string.gsub(result, "([%.,;!%?])%s*[%.,;!%?]", "%1")
        result = collapsed
        if n == 0 then
            break
        end
    end
    result = string.gsub(result, "^%s*[%.,;!%?]+%s*", "")
    return trim(result)
end

--Split one tier line into clauses on . , ; ! ? -- each clause trimmed,
--empties dropped, and each kept with its POSITION: { text, from, to },
--1-based inclusive byte offsets of the trimmed clause in the original
--line. The offsets are what lets a display highlight the recognized words
--in place (EncounterScript.MarkupRules).
--
--! and ? are separators because flavour prose in front of a mechanical
--clause is the norm ("You make off with some potions! Each party member
--gains one Healing Potion"); without them the whole line is one
--unrecognized clause and the mechanical half never lands.
--A span the author braced comes back with hidden = true.
--
--Each span also keeps `sep`, the punctuation character that ended it ("" at
--the end of the line). The split is a parsing device, not how the line
--should READ, so anything that puts clauses back in front of a player
--(EncounterMontage.ApplyEffects) uses `sep` to rebuild the sentence the
--author wrote.
local function SplitClauseSpans(text)
    text = text or ""
    local spans = {}
    local hidden = HiddenRanges(text)
    local n = #text
    local pos = 1
    while pos <= n + 1 do
        local cut = string.find(text, "[%.,;!%?]", pos)
        local last = (cut or n + 1) - 1
        if last >= pos then
            local piece = string.sub(text, pos, last)
            --trim by measuring what comes off each end, so the offsets
            --still point at the clause inside the untouched line.
            local from = pos + #string.match(piece, "^%s*")
            local to = last - #string.match(piece, "%s*$")
            --a braced clause is still parsed and applied; it is only
            --withheld from the display. The braces themselves are trimmed
            --off the ends so the grammar sees the clause as written.
            local isHidden = to >= from and (InHiddenRange(hidden, from) or InHiddenRange(hidden, to))
            while to >= from and string.match(string.sub(text, from, from), "^[{}%s]") ~= nil do
                from = from + 1
            end
            while to >= from and string.match(string.sub(text, to, to), "^[{}%s]") ~= nil do
                to = to - 1
            end
            if to >= from then
                local clause = string.gsub(string.sub(text, from, to), "[{}]", "")
                local sep = ""
                if cut ~= nil then
                    sep = string.sub(text, cut, cut)
                end
                spans[#spans + 1] = { text = trim(clause), from = from, to = to, hidden = isHidden, sep = sep }
            end
        end
        if cut == nil then
            break
        end
        pos = cut + 1
    end
    return spans
end

--Just the clause text, in order.
local function SplitClauses(text)
    local result = {}
    for _, span in ipairs(SplitClauseSpans(text)) do
        result[#result + 1] = span.text
    end
    return result
end

--Match "you <verb> <rest>" or "each party member[s] <verb>[s] <rest>" and
--return the single capture in <rest> plus the target it landed on. <verb> is
--a plain word ("gain", "heal"); the party spelling adds the "s".
local function MatchSelfOrParty(lc, verb, rest)
    local capture = string.match(lc, "^you " .. verb .. " " .. rest .. "$")
    if capture ~= nil then
        return capture, "self"
    end
    capture = string.match(lc, "^each party members? " .. verb .. "s? " .. rest .. "$")
    if capture ~= nil then
        return capture, "party"
    end
    return nil
end

--Match one clause against the effect grammar. Matching is case-insensitive
--but names are taken from the original text (position captures), so an item
--or monster name keeps its spelling.
local function ParseClause(clause)
    local lc = lower(clause)

    --"Edge on Capture Them": a standing edge or bane on another test of
    --this montage, for whoever takes it. Matched FIRST because the generic
    --"you gain <qty> <item>" rule below would otherwise read "you gain an
    --edge on Capture Them" as one item called "edge on Capture Them".
    local modEffect, modName = EncounterScript.ParseTestModClause(clause)
    if modEffect ~= nil then
        return { kind = "testmod", effect = modEffect, name = modName,
            key = EncounterScript.MatchKey(modName), text = clause }
    end

    --- boons --------------------------------------------------------------
    --These are matched BEFORE the generic "you gain <qty> <item>" rule
    --below, which would otherwise swallow "you gain 5 temporary stamina" as
    --an item named "temporary stamina".

    --Surges only exist inside a fight, so "at the start of the next combat"
    --is flavor on a clause that is deferred to the encounter anyway. The
    --clause splitter cuts it off at a comma (recognized as narrative below);
    --without the comma it is stripped here.
    local boon = string.gsub(lc, "^at the start of the next %a+,?%s*", "")

    --"you gain <n> temporary stamina" / "each party member gains <n> ..."
    local word, target = MatchSelfOrParty(lc, "gain", "(%S+) temporary stamina")
    if word ~= nil and EncounterScript.ParseQuantity(word) ~= nil then
        return { kind = "temphp", target = target, qty = EncounterScript.ParseQuantity(word), text = clause }
    end

    --"you heal <n> stamina" ("regain"/"recover" are spelled the same way)
    for _, verb in ipairs({ "heal", "regain", "recover" }) do
        word, target = MatchSelfOrParty(lc, verb, "(%S+) stamina")
        if word ~= nil and EncounterScript.ParseQuantity(word) ~= nil then
            return { kind = "heal", target = target, qty = EncounterScript.ParseQuantity(word), text = clause }
        end
    end

    --"you gain <n> surge[s]" / "each party member gains <n> surge[s]"
    word, target = MatchSelfOrParty(boon, "gain", "(%S+) surges?")
    if word ~= nil and EncounterScript.ParseQuantity(word) ~= nil then
        return { kind = "surges", target = target, qty = EncounterScript.ParseQuantity(word), text = clause }
    end

    --"your recovery value is increased by <n>" / "+<n> recovery value"
    local n = string.match(lc, "^your recovery value is increased by (%S+)$")
        or string.match(lc, "^%+?%s*(%S+) recovery value$")
        or string.match(lc, "^you gain (%S+) recovery value$")
    if n ~= nil and EncounterScript.ParseQuantity(n) ~= nil then
        return { kind = "recovery", target = "self", qty = EncounterScript.ParseQuantity(n), text = clause }
    end
    n = string.match(lc, "^each party members?'?s? recovery value is increased by (%S+)$")
    if n ~= nil and EncounterScript.ParseQuantity(n) ~= nil then
        return { kind = "recovery", target = "party", qty = EncounterScript.ParseQuantity(n), text = clause }
    end

    --"you lose a recovery" / "each party member loses two recoveries": the
    --recovery is gone off the hero's pool, with no Stamina back for it (a
    --montage cost, not Draw Steel's recovery SPEND).
    for _, noun in ipairs({ "recovery", "recoveries" }) do
        word, target = MatchSelfOrParty(lc, "lose", "(%S+) " .. noun)
        if word ~= nil and EncounterScript.ParseQuantity(word) ~= nil then
            return { kind = "loserecovery", target = target, qty = EncounterScript.ParseQuantity(word), text = clause }
        end
    end

    --"+<n> hero token[s]" / "you gain <n> hero token[s]". Hero tokens are one
    --pool the whole party draws on, so there is no self/party distinction.
    n = string.match(lc, "^%+?%s*(%S+) hero tokens?$")
        or string.match(lc, "^you gain (%S+) hero tokens?$")
        or string.match(lc, "^gain %+?(%S+) hero tokens?$")
        or string.match(lc, "^the party gains (%S+) hero tokens?$")
        or string.match(lc, "^each party members? gains? (%S+) hero tokens?$")
    if n ~= nil and EncounterScript.ParseQuantity(n) ~= nil then
        return { kind = "herotoken", qty = EncounterScript.ParseQuantity(n), text = clause }
    end

    --"+1 Intelligence" / "you gain 2 intelligence": the party's shared
    --Intelligence pool -- what they understand about the ground and the
    --enemy, spent on the Tactical Preparation screen when combat comes.
    --One pool for the whole party, like hero tokens, so there is no
    --self/party distinction. Only a script that unlocks the feature
    --("Unlock: Intelligence" in a narrative beat) has a pool to fill.
    n = string.match(lc, "^%+?%s*(%S+) intelligence$")
        or string.match(lc, "^you gain (%S+) intelligence$")
        or string.match(lc, "^gain %+?(%S+) intelligence$")
        or string.match(lc, "^the party gains (%S+) intelligence$")
        or string.match(lc, "^each party members? gains? (%S+) intelligence$")
    if n ~= nil and EncounterScript.ParseQuantity(n) ~= nil then
        return { kind = "intelligence", qty = EncounterScript.ParseQuantity(n), text = clause }
    end

    --"you gain <qty> <item>"
    local qty, pos = string.match(lc, "^you gain (%S+) ()%S")
    if qty ~= nil and EncounterScript.ParseQuantity(qty) ~= nil then
        return { kind = "item", target = "self", qty = EncounterScript.ParseQuantity(qty),
                 name = trim(string.sub(clause, pos)), text = clause }
    end

    --"each party member[s] gain[s] <qty> <item>"
    qty, pos = string.match(lc, "^each party members? gains? (%S+) ()%S")
    if qty ~= nil and EncounterScript.ParseQuantity(qty) ~= nil then
        return { kind = "item", target = "party", qty = EncounterScript.ParseQuantity(qty),
                 name = trim(string.sub(clause, pos)), text = clause }
    end

    --"you lose <n> stamina"
    local n = string.match(lc, "^you lose (%S+) stamina$")
    if n ~= nil and EncounterScript.ParseQuantity(n) ~= nil then
        return { kind = "stamina", target = "self", qty = EncounterScript.ParseQuantity(n), text = clause }
    end

    --"each party member[s] lose[s] <n> stamina"
    n = string.match(lc, "^each party members? loses? (%S+) stamina$")
    if n ~= nil and EncounterScript.ParseQuantity(n) ~= nil then
        return { kind = "stamina", target = "party", qty = EncounterScript.ParseQuantity(n), text = clause }
    end

    --"+<n> malice" / "<n> malice" / "gain <n> malice"
    n = string.match(lc, "^%+?%s*(%S+) malice$") or string.match(lc, "^gain %+?(%S+) malice$")
    if n ~= nil and EncounterScript.ParseQuantity(n) ~= nil then
        return { kind = "malice", qty = EncounterScript.ParseQuantity(n), text = clause }
    end

    --"a <monster> joins you" / "an <monster> joins you" / "<monster> joins you"
    pos = string.match(lc, "^an? ()%S.- joins you$") or string.match(lc, "^()%S.- joins you$")
    if pos ~= nil then
        local name = string.sub(clause, pos)
        name = trim(string.sub(name, 1, #name - #" joins you"))
        if name ~= "" then
            return { kind = "ally", name = name, text = clause }
        end
    end

    --"the threat is vanquished" / "threat vanquished" / "you vanquish the threat"
    if string.match(lc, "^the threat is vanquished$") or string.match(lc, "^threat vanquished$")
        or string.match(lc, "^you vanquish the threat$") or string.match(lc, "^each party member vanquishes the threat$") then
        return { kind = "vanquish", text = clause }
    end

    --"you know the stamina of goblins": monster intelligence, party-wide and
    --for the whole campaign (it lands in the shared monsterKnowledge document).
    local keyword = EncounterScript.ParseKnowStaminaClause(lc)
    if keyword ~= nil then
        return { kind = "knowstamina", keyword = keyword, text = clause }
    end

    --"reveal traps during the next combat": the Trap zones become visible
    --to the players (and their zone overlay is switched on) for the fight.
    local zone = EncounterScript.ParseRevealZonesClause(lc)
    if zone ~= nil then
        return { kind = "revealzones", zone = zone, text = clause }
    end

    --"the encounter begins with a fair roll": take back an unfavourable
    --initiative decision. Matched BEFORE the two clauses below, whose
    --"^you .*surprised$" rules would read "you are no longer surprised" as
    --its own opposite.
    if EncounterScript.ParseFairInitiativeClause(lc) then
        return { kind = "fairinitiative", text = clause }
    end

    --"you cannot be surprised": party-wide immunity for the next encounter.
    --Checked BEFORE the initiative clauses, whose "^you .*surprised$" rule
    --would otherwise read this as its own opposite (the heroes begin the
    --encounter surprised).
    if EncounterScript.ParseSurpriseImmunityClause(lc) then
        return { kind = "nosurprise", text = clause }
    end

    --Initiative outcomes for the NEXT encounter. The last one applied
    --during the montage wins (a later tier or consequence overrides an
    --earlier one). "surprised"/"surprise" also lose/win initiative and put
    --the surprised condition on every creature of the losing side.
    local outcome = EncounterScript.ParseInitiativeClause(lc)
    if outcome ~= nil then
        return { kind = "initiative", outcome = outcome, text = clause }
    end

    --"Unlock Interrogate the Goblin": a "(Locked)" entry of this montage
    --joins the board (immediately, or when its round comes round).
    local unlockName = EncounterScript.ParseUnlockClause(clause)
    if unlockName ~= nil then
        return { kind = "unlock", name = unlockName, key = EncounterScript.MatchKey(unlockName), text = clause }
    end

    --"you fail (at) the test" and friends: narrative, recognized. A bare
    --"at the start of the next combat" is the lead-in of a boon clause the
    --splitter cut at its comma -- recognized so it warns about nothing.
    if string.match(lc, "^you fail") or string.match(lc, "^you succeed") or string.match(lc, "^nothing happens")
        or string.match(lc, "^at the start of the next %a+$") then
        return { kind = "narrative", text = clause }
    end

    return { kind = "narrative", text = clause, unrecognized = true }
end

--The key a heading name is matched by, so an author does not have to copy
--it letter for letter: lower-cased, whitespace collapsed, a leading
--"the " and trailing punctuation dropped. Both sides of a clause that
--names something -- "Unlock <entry>", "Edge on <option>" -- go through it.
function EncounterScript.MatchKey(name)
    local key = lower(trim(name or ""))
    key = string.gsub(key, "%s+", " ")
    key = string.gsub(key, "^the ", "")
    key = string.gsub(key, "[%.,;:!%?]+$", "")
    return trim(key)
end

--"Unlock Interrogate the Goblin" and its spellings. Returns the entry
--name as written (so a warning or an applied line can quote the author),
--or nil. The name is matched against the montage's "(Locked)" entries by
--EncounterScript.MatchKey, at parse time (a warning) and at run time.
--  "unlock interrogate the goblin" / "unlocks ..."
--  "you unlock ..." / "the party unlocks ..." / "each party member unlocks ..."
function EncounterScript.ParseUnlockClause(clause)
    local lc = lower(clause or "")
    for _, pattern in ipairs({
        "^unlocks?%s+",
        "^you unlocks?%s+",
        "^the party unlocks?%s+",
        "^each party members? unlocks?%s+",
    }) do
        local _, stop = string.find(lc, pattern)
        if stop ~= nil then
            local name = trim(string.sub(clause, stop + 1))
            if name ~= "" then
                return name
            end
        end
    end
    return nil
end

--"Edge on Capture Them" and its spellings: a standing edge or bane on
--another test of this montage, for WHOEVER takes it -- unlike a "|Edge:"
--rider, which is weighed against the acting hero's own facts. Returns the
--rider effect key ("edge" / "doubleedge" / "bane" / "doublebane") and the
--option name as written, or nil.
--  "edge on capture them" / "double bane on capture them"
--  "an edge on capture them" / "a bane on ..."
--  "you gain an edge on ..." / "the party has an edge on ..."
--  "each party member gains an edge on ..." / "everyone gains ..."
function EncounterScript.ParseTestModClause(clause)
    local lc = lower(clause or "")
    local offset = 0
    --strip an optional lead-in, then an optional article, keeping track of
    --how far in we are so the name keeps its original spelling.
    for _, lead in ipairs({
        "^you gain%s+", "^you have%s+", "^you get%s+", "^you now have%s+",
        "^the party gains%s+", "^the party has%s+", "^the party gets%s+",
        "^each party members? gains?%s+", "^each party members? has%s+",
        "^each party members? have%s+",
        "^everyone gains%s+", "^everyone has%s+",
        "^all players gain%s+", "^every hero gains%s+",
    }) do
        local _, stop = string.find(lc, lead)
        if stop ~= nil then
            offset = stop
            break
        end
    end
    local rest = string.sub(lc, offset + 1)
    local _, article = string.find(rest, "^an?%s+")
    if article ~= nil then
        offset = offset + article
        rest = string.sub(lc, offset + 1)
    end
    local double, word, tail = string.match(rest, "^(double%s+)(edge)%s+on%s+(.+)$")
    if word == nil then
        double, word, tail = string.match(rest, "^(double%s+)(bane)%s+on%s+(.+)$")
    end
    if word == nil then
        word, tail = string.match(rest, "^(edge)%s+on%s+(.+)$")
    end
    if word == nil then
        word, tail = string.match(rest, "^(bane)%s+on%s+(.+)$")
    end
    if word == nil or trim(tail) == "" then
        return nil
    end
    local effect = cond(double ~= nil, "double" .. word, word)
    --the name as the author spelled it: everything after the matched head.
    local name = trim(string.sub(clause, offset + (#rest - #tail) + 1))
    if name == "" then
        return nil
    end
    return effect, name
end

--The player-facing line for a standing edge/bane: "The party has an edge
--on Capture Them".
function EncounterScript.DescribeTestMod(effect, name)
    local label = lower(EncounterScript.RiderLabel(effect))
    return string.format("The party has %s %s on %s",
        cond(string.match(label, "^[aeiou]") ~= nil, "an", "a"), label, name)
end

--The player-facing line for an unlock: "Interrogate the Goblin is now
--available". Only ever seen when the author left the clause unbraced.
function EncounterScript.DescribeUnlock(name)
    return string.format("%s is now available", name)
end

--"You know the Stamina of Goblins" and its spellings. Returns the monster
--keyword, lower-cased and singular ("goblins" -> "goblin"), or nil. The
--keyword is matched at run time against each monster's stat-block keywords
--(MonsterKnowledge), so "Goblin" covers everything the rules tag Goblin:
--goblins, bugbears, hobgoblins, worgs and so on.
--  "you know the stamina of goblins" / "you learn the stamina of goblins"
--  "the party knows the stamina of goblins"
--  "each party member knows the stamina of goblins"
--  "you know the stamina of the goblins" / "... of every goblin" / "... of all goblins"
function EncounterScript.ParseKnowStaminaClause(lc)
    lc = trim(lc)
    local rest = string.match(lc, "^you (.+)$")
        or string.match(lc, "^the party (.+)$")
        or string.match(lc, "^each party members? (.+)$")
    if rest == nil then
        return nil
    end
    local keyword = string.match(rest, "^knows? the stamina of (.+)$")
        or string.match(rest, "^learns? the stamina of (.+)$")
    if keyword == nil then
        return nil
    end
    keyword = trim(keyword)
    keyword = string.match(keyword, "^the (.+)$") or string.match(keyword, "^every (.+)$")
        or string.match(keyword, "^all (.+)$") or string.match(keyword, "^any (.+)$") or keyword
    keyword = trim(keyword)
    if keyword == "" or string.find(keyword, " ", 1, true) ~= nil then
        --stat-block keywords are single words; a phrase is not one.
        return nil
    end
    if #keyword > 3 and string.sub(keyword, -1) == "s" and string.sub(keyword, -2) ~= "ss" then
        keyword = string.sub(keyword, 1, -2)
    end
    return keyword
end

--Lower-case a keyword name and drop a trailing plural "s" ("traps" ->
--"trap"; "boss" keeps its s). nil for an empty name or a phrase.
local function SingularKeyword(name)
    name = trim(lower(name or ""))
    if name == "" or string.find(name, " ", 1, true) ~= nil then
        return nil
    end
    if #name > 3 and string.sub(name, -1) == "s" and string.sub(name, -2) ~= "ss" then
        name = string.sub(name, 1, -2)
    end
    return name
end

--"Reveal Traps during the next combat" and its spellings. Returns the zone
--keyword name, lower-cased and singular ("traps" -> "trap"), or nil. The
--name is matched at run time against the map's environmental keywords, so
--any zone type an author paints can be revealed this way.
--  "reveal traps" / "reveal the traps" / "reveal the trap zones"
--  "reveal traps during the next combat" / "... in the next encounter" / "... during combat"
--  "the traps are revealed" / "the trap zones are revealed during the next combat"
function EncounterScript.ParseRevealZonesClause(lc)
    lc = trim(lc)
    --the timing suffix is flavour: the reveal always lands when combat comes.
    lc = string.gsub(lc, "%s+during the next %a+$", "")
    lc = string.gsub(lc, "%s+in the next %a+$", "")
    lc = string.gsub(lc, "%s+during combat$", "")
    lc = string.gsub(lc, "%s+in combat$", "")
    lc = string.gsub(lc, "%s+for the next %a+$", "")
    local rest = string.match(lc, "^reveal (.+)$")
    if rest == nil then
        rest = string.match(lc, "^(.-) are revealed$") or string.match(lc, "^(.-) is revealed$")
    end
    if rest == nil then
        return nil
    end
    rest = trim(rest)
    rest = string.match(rest, "^the (.+)$") or string.match(rest, "^all (.+)$")
        or string.match(rest, "^every (.+)$") or rest
    rest = string.gsub(rest, "%s+zones?$", "")
    return SingularKeyword(rest)
end

--The player-facing line for a zone reveal: "The Traps will be revealed
--during the next combat".
function EncounterScript.DescribeRevealZones(zone)
    zone = tostring(zone or "")
    local shown = string.upper(string.sub(zone, 1, 1)) .. string.sub(zone, 2) .. "s"
    return string.format("The %s will be revealed during the next combat", shown)
end

--A setup instruction under "# Encounter" (the paragraph after its label):
--  "Place 4 Snare Trap objects in Trap zones and delete other Trap zones"
--  "Place one Pit object in the Pit zones"
--  "Place 4 Snare Trap objects in Trap zones and remove the remaining Trap zones"
--Returns { kind = "placeobjects", qty, object, zone, deleteOthers } or nil.
function EncounterScript.ParseSetupInstruction(text)
    local original = trim(text or "")
    local lc = lower(original)
    lc = string.gsub(lc, "%.$", "")
    local qtyWord, rest = string.match(lc, "^place (%S+) (.+)$")
    if qtyWord == nil then
        return nil
    end
    local qty = EncounterScript.ParseQuantity(qtyWord)
    if qty == nil then
        return nil
    end
    local object, zoneText = string.match(rest, "^(.-) objects? in (.+)$")
    if object == nil then
        return nil
    end
    object = trim(object)
    local zone, tail = string.match(zoneText, "^(.-) zones?(.*)$")
    if zone == nil then
        return nil
    end
    zone = string.match(zone, "^the (.+)$") or zone
    zone = SingularKeyword(zone)
    if object == "" or zone == nil then
        return nil
    end
    tail = trim(tail or "")
    local deleteOthers = false
    if tail ~= "" then
        local verb, others = string.match(tail, "^and (%a+) (.+)$")
        if verb ~= "delete" and verb ~= "remove" then
            return nil
        end
        others = string.match(others, "^the (.+)$") or others
        others = string.match(others, "^other (.+)$") or string.match(others, "^remaining (.+)$")
            or string.match(others, "^unused (.+)$") or string.match(others, "^extra (.+)$")
        if others == nil then
            return nil
        end
        others = string.gsub(others, "%s+zones?$", "")
        if SingularKeyword(others) ~= zone then
            return nil
        end
        deleteOthers = true
    end
    --the object name keeps the author's capitalisation: it is what the
    --lookup reports when nothing matches.
    local objectStart = #("place " .. qtyWord .. " ") + 1
    local objectShown = trim(string.sub(original, objectStart, objectStart + #object - 1))
    if lower(objectShown) ~= object then
        objectShown = object
    end
    return { kind = "placeobjects", qty = qty, object = objectShown, zone = zone, deleteOthers = deleteOthers }
end

--"The encounter begins with a fair roll" and its spellings: take back an
--UNFAVOURABLE initiative decision and the party's Surprised condition, and
--leave everything in the party's favour alone. An enemy the montage
--surprised stays surprised (so the heroes still go first), and a "you win
--initiative" still stands; with nothing left decided, combat rolls for it
--as normal. This is NOT "you cannot be surprised", which withholds the
--condition but still hands the initiative to the monsters.
--  "the initiative is a fair roll" / "a fair roll for initiative"
--  "the initiative is rolled normally" / "you roll for initiative normally"
--  "the encounter begins with a fair roll" / "combat starts with a fair roll"
--  "you begin the encounter on even footing" / "... on even terms"
--  "you are no longer surprised" / "the party is no longer surprised"
local FAIR_INITIATIVE_PATTERNS = {
    "^the initiative is a fair roll$", "^initiative is a fair roll$",
    "^it is a fair roll for initiative$", "^a fair roll for initiative$",
    "^the initiative is rolled normally$", "^initiative is rolled normally$",
    "^you roll for initiative$", "^you roll for initiative normally$",
    "^you roll initiative normally$",
    "^the party rolls for initiative$", "^the party rolls for initiative normally$",
    "^the party rolls initiative normally$",
    "^the encounter begins with a fair roll$", "^the encounter starts with a fair roll$",
    "^combat begins with a fair roll$", "^combat starts with a fair roll$",
    "^the fight begins with a fair roll$", "^the fight starts with a fair roll$",
    "^you are no longer surprised$", "^the party is no longer surprised$",
    "^each party member is no longer surprised$", "^each party members are no longer surprised$",
}
function EncounterScript.ParseFairInitiativeClause(lc)
    lc = trim(lc)
    --the roll clauses may all name what is being rolled for
    lc = string.gsub(lc, "^(.*with a fair roll) for initiative$", "%1")
    for _, pattern in ipairs(FAIR_INITIATIVE_PATTERNS) do
        if string.match(lc, pattern) ~= nil then
            return true
        end
    end
    --"you begin/start the (next) encounter/combat/fight on even footing/terms"
    if string.match(lc, "^you [a-z]+ .*on even footing$") or string.match(lc, "^you [a-z]+ .*on even terms$")
        or string.match(lc, "^the party [a-z]+ .*on even footing$") or string.match(lc, "^the party [a-z]+ .*on even terms$") then
        return true
    end
    return false
end

--The player-facing line for a fair roll.
function EncounterScript.DescribeFairInitiative()
    return "The encounter begins with a fair roll for initiative"
end

--"You cannot be surprised" and its spellings. The heroes still LOSE the
--initiative to a "surprised" outcome -- only the Surprised condition is
--withheld, and from the whole party, whoever earned it.
--  "you cannot be surprised" / "can not" / "can't"
--  "the party cannot be surprised" / "each party member cannot be surprised"
--  "you are immune to surprise" / "the party is immune to surprise"
function EncounterScript.ParseSurpriseImmunityClause(lc)
    lc = trim(lc)
    local rest = string.match(lc, "^you (.+)$")
        or string.match(lc, "^the party (.+)$")
        or string.match(lc, "^each party members? (.+)$")
    if rest == nil then
        return false
    end
    return rest == "cannot be surprised" or rest == "can not be surprised"
        or rest == "can't be surprised"
        or rest == "are immune to surprise" or rest == "is immune to surprise"
        or rest == "is not surprised" or rest == "are not surprised"
end

--Match a lower-cased clause against the initiative grammar. Returns
--"surprised" (the heroes begin the encounter surprised), "surprise" (the
--heroes surprise the enemy), "win", "lose", or nil.
--  "you begin the encounter surprised" / "you start the next encounter surprised"
--  "you are surprised" / "the party begins the encounter surprised"
--  "you surprise the enemy" / "you surprise the enemies" / "the enemy is surprised"
--  "you win initiative" / "you win the initiative" / "you lose initiative"
function EncounterScript.ParseInitiativeClause(lc)
    lc = trim(lc)
    if string.match(lc, "^you win the initiative$") or string.match(lc, "^you win initiative$")
        or string.match(lc, "^the party wins the initiative$") or string.match(lc, "^the party wins initiative$") then
        return "win"
    end
    if string.match(lc, "^you lose the initiative$") or string.match(lc, "^you lose initiative$")
        or string.match(lc, "^the party loses the initiative$") or string.match(lc, "^the party loses initiative$") then
        return "lose"
    end
    if string.match(lc, "^you surprise the enem") or string.match(lc, "^the party surprises the enem")
        or string.match(lc, "^the enem[a-z]* [a-z]* surprised$") then
        return "surprise"
    end
    --"you begin/start the (next) encounter surprised", "you are surprised",
    --"the party begins ... surprised": anything by the heroes ending in
    --"surprised" that is not about the enemy.
    if string.match(lc, "^you .*surprised$") or string.match(lc, "^the party .*surprised$")
        or string.match(lc, "^each party member .*surprised$") then
        return "surprised"
    end
    return nil
end

--The roll header shown on an option card before anyone takes the roll:
--"Presence (Empathize, Lie, Flirt)" -> "Presence". The skills are only
--discovered in the roll dialog (user direction 2026-09-19).
function EncounterScript.AttrWithoutSkills(attr)
    local stripped = string.gsub(attr or "", "%s*%b()", "")
    return trim(stripped)
end

--- riders ------------------------------------------------------------------
--
--A test may carry riders: "|<Effect>: <requirement>" lines after its
--tiers (Allow / Edge / Double Edge / Bane / Double Bane, with "you are
--skilled in X" / "you speak X" / "you are a X" requirements). The grammar
--and the weighing live in core, TestRiders (DMHub Game Rules/TestRiders.lua),
--shared with the journal's own power-roll blocks; these are the names the
--rest of the codemod (and the tests) use. TestRiders is looked up at call
--time so this module still loads on its own.
local function Riders()
    local tr = rawget(_G, "TestRiders")
    if tr == nil then
        error("TestRiders (DMHub Game Rules/TestRiders.lua) is not loaded")
    end
    return tr
end

function EncounterScript.RiderLabel(effect)
    return Riders().Label(effect)
end

function EncounterScript.RiderBoons(effect)
    return Riders().Boons(effect)
end

function EncounterScript.ParseRiderLine(text)
    return Riders().ParseRiderLine(text)
end

function EncounterScript.NormalizeName(name)
    return Riders().NormalizeName(name)
end

function EncounterScript.ParseRequirement(text)
    return Riders().ParseRequirement(text)
end

function EncounterScript.RequirementMet(req, facts)
    return Riders().RequirementMet(req, facts)
end

function EncounterScript.EvaluateRiders(riders, facts)
    return Riders().Evaluate(riders, facts)
end

--Split a tier line on its first "=>" into (teaser, fullText). A line with
--no "=>" returns (nil, line). Both halves are trimmed; an empty teaser is
--returned as "" so the caller can warn.
function EncounterScript.SplitTeaser(tierText)
    local teaser, fullText = string.match(tierText or "", "^(.-)=>(.*)$")
    if teaser == nil then
        return nil, trim(tierText or "")
    end
    return trim(teaser), trim(fullText)
end

--What a tier row should read for a viewer: the full text when the tier has
--landed (or has no teaser), the teaser otherwise.
function EncounterScript.TierDisplayText(roll, t, landed)
    local teaser = roll.teasers ~= nil and roll.teasers[t] or nil
    if landed or teaser == nil then
        return EncounterScript.VisibleText(roll.tiers[t])
    end
    return EncounterScript.VisibleText(teaser)
end

--Parse a tier line (or a Consequence: line) into its effects, each with
--the position of the clause it came from: { from, to, effect }. A clause
--the author wrapped in "{...}" comes back with effect.hidden = true: it
--is applied like any other, but nothing shows it to a player.
function EncounterScript.ParseEffectSpans(text)
    local result = {}
    for _, span in ipairs(SplitClauseSpans(text or "")) do
        local effect = ParseClause(span.text)
        if span.hidden then
            effect.hidden = true
        end
        --the punctuation this clause ended on, so a run of prose clauses
        --can be shown as the one sentence it was written as.
        effect.sep = span.sep
        result[#result + 1] = { from = span.from, to = span.to, effect = effect }
    end
    return result
end

--Parse a tier line (or a Consequence: line) into its effects.
function EncounterScript.ParseEffects(text)
    local result = {}
    for _, span in ipairs(EncounterScript.ParseEffectSpans(text)) do
        result[#result + 1] = span.effect
    end
    return result
end

--Does this parsed clause actually DO anything? "narrative" is both the
--flavour the grammar recognizes as flavour ("you fail the test") and
--everything it did not understand at all; every other kind changes the
--game state.
function EncounterScript.EffectIsMechanical(effect)
    return effect ~= nil and effect.kind ~= "narrative"
end

--Wrap every mechanically recognized clause of a line in open ... close,
--leaving the flavour, the punctuation and anything the grammar did not
--understand exactly as written. The caller supplies the tags (the stage
--passes rich-text colour tags), so this stays engine-free and testable.
function EncounterScript.MarkupRules(text, open, close)
    --hidden clauses are gone before anything is highlighted, so the
    --offsets below index the text the player actually sees.
    text = EncounterScript.VisibleText(text or "")
    if open == nil or open == "" then
        return text
    end
    close = close or ""
    local out = {}
    local copied = 1
    for _, span in ipairs(EncounterScript.ParseEffectSpans(text)) do
        if EncounterScript.EffectIsMechanical(span.effect) then
            out[#out + 1] = string.sub(text, copied, span.from - 1)
            out[#out + 1] = open
            out[#out + 1] = string.sub(text, span.from, span.to)
            out[#out + 1] = close
            copied = span.to + 1
        end
    end
    if copied == 1 then
        return text
    end
    out[#out + 1] = string.sub(text, copied)
    return table.concat(out)
end

--- power roll attr ---------------------------------------------------------

--"Presence (Empathize, Lie, Flirt)" -> characteristics set + skills list.
--attributesInfo: { [attrid] = { description = "Presence", ... } }
--skillOptions:   { { id = skillid, text = "Empathize" }, ... }
--The same substring rule PowerRollDisplay's press handler uses, so a
--script rolls exactly what the journal's own power-roll link would.
function EncounterScript.ParseAttr(attr, attributesInfo, skillOptions)
    local text = lower(attr or "")
    local characteristics = {}
    for attrid, info in pairs(attributesInfo or {}) do
        local desc = info.description
        if type(desc) == "string" and desc ~= "" and string.find(text, lower(desc), 1, true) ~= nil then
            characteristics[attrid] = true
        end
    end
    local skills = {}
    for _, skillInfo in ipairs(skillOptions or {}) do
        local name = skillInfo.text
        if type(name) == "string" and name ~= "" and string.find(text, lower(name), 1, true) ~= nil then
            skills[#skills + 1] = skillInfo.id
        end
    end
    return characteristics, skills
end

--- party-size scaling -------------------------------------------------------

--A "3-5 Players: -1 Opportunity, -1 Threat" line under a "## Round N"
--heading: at that party size the round drops that many of each kind, drawn
--at random from the entries the round introduces (see ChooseRemovedEntries).
--The range may be "3", "3-5" or "3+", and "Players" may be "Heroes".
--Returns { min, max = nil when open-ended,
--          removals = { opportunity = 1, threat = 1 }, text } or nil.
function EncounterScript.ParseScalingDirective(text)
    local original = trim(text or "")
    local lc = string.gsub(lower(original), "%.$", "")
    local range, word, rest = string.match(lc, "^([%d][%d%s%-+]*)%s+(%a+)%s*:%s*(.+)$")
    if range == nil then
        return nil
    end
    if word ~= "players" and word ~= "player" and word ~= "heroes" and word ~= "hero" then
        return nil
    end
    range = trim(range)
    local min, max
    local lo, hi = string.match(range, "^(%d+)%s*%-%s*(%d+)$")
    if lo ~= nil then
        min, max = tonumber(lo), tonumber(hi)
    elseif string.match(range, "^%d+%+$") then
        min = tonumber(string.match(range, "^(%d+)%+$"))
    elseif string.match(range, "^%d+$") then
        min, max = tonumber(range), tonumber(range)
    else
        return nil
    end
    if min == nil or (max ~= nil and max < min) then
        return nil
    end

    local removals = {}
    local any = false
    for clause in string.gmatch(rest, "[^,;]+") do
        clause = trim(clause)
        if clause ~= "" then
            --"-1 opportunity"; a bare "1 opportunity" means the same thing,
            --and nothing is ever ADDED by a directive.
            local sign, qtyWord, kind = string.match(clause, "^([%-+]?)%s*(%S+)%s+(%a+)$")
            if kind == nil or sign == "+" then
                return nil
            end
            local qty = EncounterScript.ParseQuantity(qtyWord)
            if qty == nil or qty < 0 then
                return nil
            end
            kind = string.gsub(kind, "ies$", "y")
            kind = string.gsub(kind, "s$", "")
            if kind ~= "opportunity" and kind ~= "threat" then
                return nil
            end
            removals[kind] = (removals[kind] or 0) + qty
            any = true
        end
    end
    if not any then
        return nil
    end
    return { min = min, max = max, removals = removals, text = original }
end

--Does this line LOOK like a party-size directive? A typo'd one then warns
--instead of quietly becoming montage intro prose.
function EncounterScript.IsScalingDirectiveLine(text)
    local lc = lower(trim(text or ""))
    return string.match(lc, "^%d[%d%s%-+]*%s+players?%s*:") ~= nil
        or string.match(lc, "^%d[%d%s%-+]*%s+heroe?s?%s*:") ~= nil
end

--How many entries of each kind a round drops for a party of `partySize`.
--Every directive whose range covers the size applies, cumulatively.
function EncounterScript.ScalingRemovals(round, partySize)
    local removals = {}
    partySize = tonumber(partySize) or 0
    for _, d in ipairs((round and round.scaling) or {}) do
        if partySize >= d.min and (d.max == nil or partySize <= d.max) then
            for kind, n in pairs(d.removals) do
                removals[kind] = (removals[kind] or 0) + n
            end
        end
    end
    return removals
end

--Does any round of this montage carry a party-size directive?
function EncounterScript.HasScaling(beat)
    for _, r in ipairs((beat and beat.rounds) or {}) do
        if #(r.scaling or {}) > 0 then
            return true
        end
    end
    return false
end

--Does the round that introduces this entry carry a party-size directive?
--Such a round shows nothing at all until the removals have been rolled: a
--card that is about to be removed must never appear.
function EncounterScript.RoundHasScaling(beat, roundNumber)
    for _, r in ipairs((beat and beat.rounds) or {}) do
        if r.number == roundNumber and #(r.scaling or {}) > 0 then
            return true
        end
    end
    return false
end

--The entry ids a montage beat removes for a party of `partySize`, as
--{ [entryId] = true }. Candidates are only the entries the directive's own
--round INTRODUCES -- never one carried over from an earlier round -- and
--never one whose heading said "(Required)". A round that asks for more than
--it has drops everything it can.
--`rand(n)` returns an integer in 1..n; math.random by default (the tests
--pass a deterministic one).
function EncounterScript.ChooseRemovedEntries(beat, partySize, rand)
    rand = rand or function(n) return math.random(n) end
    local removed = {}
    for _, r in ipairs((beat and beat.rounds) or {}) do
        local removals = EncounterScript.ScalingRemovals(r, partySize)
        for _, kind in ipairs({ "opportunity", "threat" }) do
            local count = removals[kind] or 0
            if count > 0 then
                local pool = {}
                for _, e in ipairs(r.entries) do
                    if e.kind == kind and not e.required and not e.locked then
                        pool[#pool + 1] = e.id
                    end
                end
                for _ = 1, math.min(count, #pool) do
                    local idx = rand(#pool)
                    removed[pool[idx]] = true
                    table.remove(pool, idx)
                end
            end
        end
    end
    return removed
end

--- the document ------------------------------------------------------------

--- scenes ------------------------------------------------------------------------
--
--A montage entry may carry a SCENE: after a "---" line in the entry's body,
--each line is one step played on the stage when a hero approaches (see
--"Montage scenes" in EncounterOfTheWeek.md). In such an entry an option's
--lines above its power roll play once the option is picked, and its lines
--below the roll play once the roll has landed. Grammar, one step per line:
--  PC: I see a witch!                speech ("PC" is the approaching hero)
--  Witch: (in Hyrallic) Oh spirits   speech in a language
--  Witch (Hag) enters                a character comes on stage; the
--                                    parenthesis names the bestiary monster
--                                    whose portrait is shown
--  Witch exits                       and leaves again
--  Witch is alarmed                  an emote (alert, scared, alarmed),
--  Goblin (scared): Let go!          alone or on a line of speech; it
--                                    plays as the next line appears
--  if PC speaks Hyrallic then        branches: if / elseif / else / end
--  anything else                     narration
--The compiled scene is a tree of steps; FlattenScene walks it for one hero
--and one roll and returns the lines that actually play.

local SCENE_ENTER_VERBS = { enters = true, appears = true, arrives = true }
local SCENE_EXIT_VERBS = { exits = true, leaves = true, departs = true }
--Emotes a character can show ("Witch is alarmed", "Goblin (scared): ...").
EncounterScript.SCENE_EMOTES = { alert = true, scared = true, alarmed = true }

--The named sections of a "# Delve: <Name>" (lowered heading -> key), besides
--its "## Obstacle: ..." entries: the chest (scene + dice table), the scene
--offering to press on, and the scenes for walking out and being forced out.
EncounterScript.DELVE_SECTIONS = {
    ["chest"] = "chest",
    ["continue"] = "continue",
    ["leave"] = "leave",
    ["turn back"] = "leave",
    ["forced out"] = "forced",
}

--"Witch (Hag) enters" -> "Witch", "Hag"; "Witch enters" -> "Witch", "Witch".
local function ParseEnterLine(line)
    local body, verb = string.match(line, "^(.-)%s+(%a+)[%.!]*$")
    if body == nil or not SCENE_ENTER_VERBS[lower(verb)] then
        return nil
    end
    local name, monster = string.match(body, "^(.-)%s*%(([^()]+)%)$")
    if name == nil then
        name, monster = body, body
    end
    name, monster = trim(name), trim(monster)
    if name == "" or monster == "" or lower(name) == "pc" then
        return nil
    end
    return name, monster
end

local function ParseExitLine(line)
    local name, verb = string.match(line, "^(.-)%s+(%a+)[%.!]*$")
    if name == nil or not SCENE_EXIT_VERBS[lower(verb)] then
        return nil
    end
    return trim(name)
end

--One condition atom ("pc speaks hyrallic", "tier 2", "crit") -> a node.
local function ParseConditionAtom(text)
    local s = trim(text)
    local n = string.match(s, "^tier%s*(%d)$")
    if n ~= nil then
        return { op = "tier", tier = tonumber(n) }
    end
    local words = { one = 1, two = 2, three = 3 }
    local w = string.match(s, "^tier%s+(%a+)$")
    if w ~= nil and words[w] ~= nil then
        return { op = "tier", tier = words[w] }
    end
    if s == "crit" or s == "critical" or s == "critical success" or s == "a critical success" then
        return { op = "tier", tier = 4 }
    end
    local name = string.match(s, "^pc does not speak (.+)$") or string.match(s, "^pc doesn't speak (.+)$")
    if name ~= nil then
        return { op = "not", a = { op = "speaks", name = trim(name) } }
    end
    name = string.match(s, "^pc speaks (.+)$") or string.match(s, "^pc knows (.+)$")
    if name ~= nil then
        return { op = "speaks", name = trim(name) }
    end
    name = string.match(s, "^pc is skilled in (.+)$") or string.match(s, "^pc has (.+)$")
    if name ~= nil then
        return { op = "has", name = trim(name) }
    end
    name = string.match(s, "^pc is an? (.+)$") or string.match(s, "^pc is (.+)$")
    if name ~= nil then
        return { op = "is", name = trim(name) }
    end
    name = string.match(s, "^pc chose (.+)$") or string.match(s, "^pc chooses (.+)$")
    if name ~= nil then
        return { op = "chose", name = trim(name) }
    end
    return { op = "unknown", text = s }
end

--"not", "and", "or" and parentheses around atoms; "and" binds tighter than
--"or". Returns the condition tree and a list of problems (strings).
function EncounterScript.ParseCondition(text)
    local problems = {}
    local src = lower(trim(text or ""))
    src = string.gsub(src, "%s+then$", "")
    src = string.gsub(src, "%(", " ( ")
    src = string.gsub(src, "%)", " ) ")
    local tokens = {}
    for tok in string.gmatch(src, "%S+") do
        tokens[#tokens + 1] = tok
    end
    local pos = 1

    local ParseOr
    local function ParseUnary()
        local tok = tokens[pos]
        if tok == "not" then
            pos = pos + 1
            return { op = "not", a = ParseUnary() }
        end
        if tok == "(" then
            pos = pos + 1
            local node = ParseOr()
            if tokens[pos] == ")" then
                pos = pos + 1
            else
                problems[#problems + 1] = "missing ')'"
            end
            return node
        end
        local words = {}
        while tokens[pos] ~= nil and tokens[pos] ~= "and" and tokens[pos] ~= "or" and tokens[pos] ~= ")" do
            words[#words + 1] = tokens[pos]
            pos = pos + 1
        end
        if #words == 0 then
            problems[#problems + 1] = "a condition is missing"
            return { op = "unknown", text = "" }
        end
        local atom = ParseConditionAtom(table.concat(words, " "))
        if atom.op == "unknown" then
            problems[#problems + 1] = string.format("'%s' is not a condition (use 'PC speaks X', 'PC is X', 'PC has X', 'PC chose X', 'tier1'-'tier3' or 'crit')", atom.text)
        end
        return atom
    end
    local function ParseAnd()
        local node = ParseUnary()
        while tokens[pos] == "and" do
            pos = pos + 1
            node = { op = "and", a = node, b = ParseUnary() }
        end
        return node
    end
    ParseOr = function()
        local node = ParseAnd()
        while tokens[pos] == "or" do
            pos = pos + 1
            node = { op = "or", a = node, b = ParseAnd() }
        end
        return node
    end

    local tree = ParseOr()
    if tokens[pos] ~= nil then
        problems[#problems + 1] = string.format("unexpected '%s'", tokens[pos])
    end
    return tree, problems
end

--Does a condition mention the roll's tier anywhere?
local function ConditionUsesTier(node)
    if node == nil then
        return false
    end
    if node.op == "tier" then
        return true
    end
    return ConditionUsesTier(node.a) or ConditionUsesTier(node.b)
end

--Every character a scene brings on stage, keyed by lowered name. Speech is
--only recognized from these (and PC), so narration with a colon in it
--("Beware: the path is steep") stays narration.
function EncounterScript.SceneActors(rawLists)
    local actors = {}
    for _, list in ipairs(rawLists) do
        for _, raw in ipairs(list or {}) do
            local name, monster = ParseEnterLine(raw.text)
            if name ~= nil and actors[lower(name)] == nil then
                actors[lower(name)] = { name = name, monster = monster }
            end
        end
    end
    return actors
end

--Compile one run of raw scene lines ({ text, line }) into a step tree.
--`part` is "intro", "option" or "outcome": only an outcome knows the tier.
--`warn(line, fmt, ...)` reports authoring problems.
function EncounterScript.CompileScene(rawLines, actors, part, warn)
    local root = { steps = {} }
    --the stack of open blocks; each frame is { node = ifNode, steps = the
    --branch list lines are being added to }.
    local stack = {}
    local function Current()
        if #stack == 0 then
            return root.steps
        end
        return stack[#stack].steps
    end
    local function Condition(text, lineNo)
        local tree, problems = EncounterScript.ParseCondition(text)
        for _, p in ipairs(problems) do
            warn(lineNo, "scene condition '%s': %s", trim(text), p)
        end
        if part ~= "outcome" and ConditionUsesTier(tree) then
            warn(lineNo, "scene condition '%s' tests the tier, which is only known in the lines below an option's power roll; it is never true here", trim(text))
        end
        return tree
    end

    for _, raw in ipairs(rawLines or {}) do
        local line = trim(raw.text)
        local lc = lower(line)
        local lineNo = raw.line
        local ifCond = string.match(line, "^[iI][fF]%s+(.+)$")
        local elseifCond = string.match(line, "^[eE][lL][sS][eE]%s*[iI][fF]%s+(.+)$")
        --narration may begin with "If" ("If you listen closely..."): it is
        --a branch only when it ends in "then" or reads as a condition.
        local function IsBranch(condText)
            if condText == nil then
                return false
            end
            if string.match(lower(condText), "%s+then$") ~= nil then
                return true
            end
            local _, problems = EncounterScript.ParseCondition(condText)
            return #problems == 0
        end
        if not IsBranch(elseifCond) then
            elseifCond = nil
        end
        if elseifCond == nil and not IsBranch(ifCond) then
            ifCond = nil
        end
        if elseifCond ~= nil then
            local frame = stack[#stack]
            if frame == nil or frame.inElse then
                warn(lineNo, "'%s' has no 'if' above it; ignored", line)
            else
                local branch = { cond = Condition(elseifCond, lineNo), steps = {} }
                frame.node.branches[#frame.node.branches + 1] = branch
                frame.steps = branch.steps
            end
        elseif ifCond ~= nil then
            local node = { kind = "if", line = lineNo, branches = {} }
            local branch = { cond = Condition(ifCond, lineNo), steps = {} }
            node.branches[1] = branch
            local list = Current()
            list[#list + 1] = node
            stack[#stack + 1] = { node = node, steps = branch.steps }
        elseif lc == "else" or lc == "else:" or lc == "otherwise" then
            local frame = stack[#stack]
            if frame == nil or frame.inElse then
                warn(lineNo, "'%s' has no 'if' above it; ignored", line)
            else
                frame.node.elseSteps = {}
                frame.steps = frame.node.elseSteps
                frame.inElse = true
            end
        elseif lc == "end" or lc == "end if" or lc == "endif" then
            if #stack == 0 then
                warn(lineNo, "'end' has no 'if' above it; ignored")
            else
                stack[#stack] = nil
            end
        else
            local step = nil
            local enterName, monster = ParseEnterLine(line)
            local exitName = ParseExitLine(line)
            --"Witch is alarmed": only for PC or a character of the scene,
            --so "The forest is alert" stays narration.
            local emoteName, emoteWord = string.match(line, "^(.-)%s+is%s+(%a+)[%.!]*$")
            local emoteKey = emoteName ~= nil and lower(trim(emoteName)) or nil
            if emoteKey ~= nil and not (EncounterScript.SCENE_EMOTES[lower(emoteWord)] and (emoteKey == "pc" or actors[emoteKey] ~= nil)) then
                emoteKey = nil
            end
            if enterName ~= nil then
                step = { kind = "enter", name = enterName, monster = monster, line = lineNo }
            elseif exitName ~= nil and actors[lower(exitName)] ~= nil then
                step = { kind = "exit", name = actors[lower(exitName)].name, line = lineNo }
            elseif emoteKey ~= nil then
                step = {
                    kind = "emote",
                    name = cond(emoteKey == "pc", "PC", actors[emoteKey] ~= nil and actors[emoteKey].name or ""),
                    emote = lower(emoteWord),
                    line = lineNo,
                }
            else
                local speaker, said = string.match(line, "^([^:]+):%s*(.+)$")
                --"Goblin (scared): Let go!" -- an emote on the speaker.
                local speakerEmote = nil
                if speaker ~= nil then
                    local bare, word = string.match(trim(speaker), "^(.-)%s*%((%a+)%)$")
                    if bare ~= nil and EncounterScript.SCENE_EMOTES[lower(word)] then
                        speaker = bare
                        speakerEmote = lower(word)
                    end
                end
                local key = speaker ~= nil and lower(trim(speaker)) or nil
                if key ~= nil and (key == "pc" or actors[key] ~= nil) then
                    local lang, rest = string.match(said, "^%(%s*[iI][nN]%s+([^)]-)%s*%)%s*(.*)$")
                    step = {
                        kind = "say",
                        speaker = cond(key == "pc", "PC", actors[key] ~= nil and actors[key].name or trim(speaker)),
                        text = cond(lang ~= nil, rest, said),
                        lang = lang,
                        emote = speakerEmote,
                        line = lineNo,
                    }
                else
                    step = { kind = "narrate", text = line, line = lineNo }
                end
            end
            local list = Current()
            list[#list + 1] = step
        end
    end
    if #stack > 0 then
        warn(stack[#stack].node.line, "'if' is never closed with 'end'; closed at the end of the scene")
    end
    return root.steps
end

--Evaluate a condition tree. `test(atom)` answers one atom (speaks / is /
--has / chose); tiers are compared here. tier3 also holds on a critical.
local function EvalCondition(node, test, tier)
    if node == nil then
        return false
    end
    local op = node.op
    if op == "and" then
        return EvalCondition(node.a, test, tier) and EvalCondition(node.b, test, tier)
    elseif op == "or" then
        return EvalCondition(node.a, test, tier) or EvalCondition(node.b, test, tier)
    elseif op == "not" then
        return not EvalCondition(node.a, test, tier)
    elseif op == "tier" then
        if tier == nil then
            return false
        end
        if node.tier == 3 then
            return tier >= 3
        end
        return tier == node.tier
    elseif op == "unknown" then
        return false
    end
    return test(node) == true
end

EncounterScript.EvalCondition = EvalCondition

--Walk a compiled scene for one playing and return the lines that play:
--{ { kind = "narrate"|"say", text, speaker, lang, line,
--    cast = { { name, monster }, ... },
--    emotes = nil | { { name ("PC" or a character), emote }, ... } }, ... }. `cast` is who is on the
--right-hand side of the stage while that line shows (the hero is always on
--the left). Entrances and exits are not lines of their own -- they land with
--the next line -- and `cast` (the list the scene starts with) is updated in
--place, so a scene part hands its final cast on to the next part.
--A character who speaks before entering is brought on as they speak.
--`env` = { test = function(atomNode) -> bool, tier = n|nil, actors = map }.
function EncounterScript.FlattenScene(steps, env, cast)
    local out = {}
    local function Snapshot()
        local copy = {}
        for i, c in ipairs(cast) do
            copy[i] = { name = c.name, monster = c.monster }
        end
        return copy
    end
    local function OnStage(name)
        for i, c in ipairs(cast) do
            if lower(c.name) == lower(name) then
                return i
            end
        end
        return nil
    end
    --emotes wait for the next line that plays, like entrances do.
    local pendingEmotes = {}
    local function Walk(list)
        for _, step in ipairs(list or {}) do
            if step.kind == "emote" then
                pendingEmotes[#pendingEmotes + 1] = { name = step.name, emote = step.emote }
            elseif step.kind == "if" then
                local taken = nil
                for _, branch in ipairs(step.branches) do
                    if EvalCondition(branch.cond, env.test, env.tier) then
                        taken = branch.steps
                        break
                    end
                end
                if taken == nil then
                    taken = step.elseSteps
                end
                Walk(taken)
            elseif step.kind == "enter" then
                if OnStage(step.name) == nil then
                    cast[#cast + 1] = { name = step.name, monster = step.monster }
                end
            elseif step.kind == "exit" then
                local i = OnStage(step.name)
                if i ~= nil then
                    table.remove(cast, i)
                end
            else
                if step.kind == "say" and step.speaker ~= "PC" and OnStage(step.speaker) == nil then
                    local actor = (env.actors or {})[lower(step.speaker)]
                    cast[#cast + 1] = { name = step.speaker, monster = actor ~= nil and actor.monster or step.speaker }
                end
                if step.emote ~= nil then
                    pendingEmotes[#pendingEmotes + 1] = { name = step.speaker, emote = step.emote }
                end
                out[#out + 1] = {
                    kind = step.kind,
                    text = step.text,
                    speaker = step.speaker,
                    lang = step.lang,
                    line = step.line,
                    cast = Snapshot(),
                    emotes = cond(#pendingEmotes > 0, pendingEmotes, nil),
                }
                pendingEmotes = {}
            end
        end
    end
    Walk(steps)
    return out
end

--Replace the word "PC" (and "PC's") with the hero's name.
function EncounterScript.SubstitutePC(text, heroName)
    local result = string.gsub(text or "", "%f[%w]PC%f[%W]", function()
        return heroName
    end)
    return result
end

--Words in a language the hero does not know: every letter is swapped for
--another, deterministically (the same line always garbles the same way),
--keeping case, spacing and punctuation so it still reads as speech.
function EncounterScript.Garble(text, language)
    local seed = 7
    for i = 1, #(language or "") do
        seed = (seed * 31 + string.byte(language, i)) % 9973
    end
    local vowels = "aeiouy"
    local consonants = "bcdfghjklmnpqrstvwxz"
    local n = 0
    local result = string.gsub(text or "", "%a", function(ch)
        n = n + 1
        local isUpper = ch ~= string.lower(ch)
        local lc = string.lower(ch)
        local pool = cond(string.find(vowels, lc, 1, true) ~= nil, vowels, consonants)
        local idx = string.find(pool, lc, 1, true) or 1
        local shifted = ((idx - 1 + seed + n * 7) % #pool) + 1
        local out = string.sub(pool, shifted, shifted)
        if isUpper then
            out = string.upper(out)
        end
        return out
    end)
    return result
end

local function SplitLines(text)
    local lines = {}
    text = string.gsub(text or "", "\r\n", "\n")
    text = string.gsub(text, "\r", "\n")
    --the journal stores a soft line break (shift+enter) as a vertical
    --tab; its own renderer treats it as a newline, so we must too, or a
    --rider typed that way rides along inside the tier line above it.
    text = string.gsub(text, "\v", "\n")
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

EncounterScript.SplitLines = SplitLines

--- sub-documents -------------------------------------------------------------
--
--A week's script can be spread over several journal documents. A line that
--is NOTHING BUT a link to another document -- the journal's page embed
--"[:Name]", a full link "[label](target)", or the "[Name]" shorthand -- is
--replaced by that document's text, recursively, before the script is
--parsed. A link inside a sentence stays a link. Design:
--EncounterOfTheWeek.md, "Splitting a script across documents".

EncounterScript.maxIncludeDepth = 8

--The link target of a line that is only a link, or nil. The same three
--forms Seamless.LinkAtPosition follows (MarkdownDocument.lua); rich [[tags]],
--checkboxes and images are not links.
function EncounterScript.IncludeTarget(line)
    local t = trim(line)
    local target = string.match(t, "^%[:([^%[%]]+)%]$")
    if target ~= nil then
        return trim(target)
    end
    local _, linkTarget = string.match(t, "^%[([^%[%]]*)%]%(([^%(%)]+)%)$")
    if linkTarget ~= nil then
        return trim(linkTarget)
    end
    local label = string.match(t, "^%[([^%[%]]+)%]$")
    if label ~= nil and not string.match(label, "^[xX ]$") then
        return trim(label)
    end
    return nil
end

--"line 12", or "'Mysterious Cottage' line 12" for a line that came from a
--document other than the script's own.
function EncounterScript.DescribeSource(src, rootId)
    if src == nil then
        return "line ?"
    end
    if src.docid == rootId then
        return string.format("line %d", src.line)
    end
    return string.format("'%s' line %d", tostring(src.name or src.docid), src.line)
end

--Splice included documents into a script's text.
--  root = { id, name, text } -- the script's own document
--  resolve(target) -> { id, name, text } for a journal document, or
--      nil, problem -- problem is nil when the link is fine but names no
--      document (a monster, a PDF, a web page): the line stays as prose;
--      otherwise a string saying what is wrong: the line stays, and warns
--Returns {
--  text = the expanded text,
--  sources = { [expandedLine] = { docid, name, line } } -- where each line of
--      the expanded text came from (line is 1-based within that document)
--  included = { [docid] = { id, name } } -- every document spliced in
--  warnings = { "...", ... },
--}
function EncounterScript.ExpandIncludes(root, resolve)
    local out, sources, warnings, included = {}, {}, {}, {}
    local function Warn(src, fmt, ...)
        warnings[#warnings + 1] = EncounterScript.DescribeSource(src, root.id) .. ": " .. string.format(fmt, ...)
    end
    local stack = {}
    local function Expand(doc, depth)
        stack[doc.id] = true
        for i, line in ipairs(SplitLines(doc.text)) do
            local src = { docid = doc.id, name = doc.name, line = i }
            local spliced = false
            local target = EncounterScript.IncludeTarget(line)
            if target ~= nil then
                local child, problem = resolve(target)
                if child == nil then
                    if problem ~= nil then
                        Warn(src, "'%s' %s; the line is left as text", target, problem)
                    end
                elseif stack[child.id] then
                    Warn(src, "'%s' includes itself; not included again", tostring(child.name or target))
                elseif depth >= EncounterScript.maxIncludeDepth then
                    Warn(src, "'%s' is nested more than %d documents deep; not included", tostring(child.name or target), EncounterScript.maxIncludeDepth)
                else
                    included[child.id] = { id = child.id, name = child.name }
                    --blank lines around the splice, so a paragraph above or
                    --below the link never runs into the included text.
                    out[#out + 1] = ""
                    sources[#out] = src
                    Expand(child, depth + 1)
                    out[#out + 1] = ""
                    sources[#out] = src
                    spliced = true
                end
            end
            if not spliced then
                out[#out + 1] = line
                sources[#out] = src
            end
        end
        stack[doc.id] = nil
    end
    Expand(root, 0)
    return { text = table.concat(out, "\n"), sources = sources, included = included, warnings = warnings }
end

--Where a line of a parsed script came from, for a message. Plain "line N"
--for a script that was parsed without ParseExpanded.
function EncounterScript.LineLabel(parse, lineIndex)
    if parse == nil or parse.sources == nil then
        return string.format("line %d", lineIndex or 0)
    end
    return EncounterScript.DescribeSource(parse.sources[lineIndex or 0], parse.rootId)
end

--Parse an ExpandIncludes result. The parse also carries `sources`, `rootId`
--and `included`; its warnings name the document each line came from, and
--the include problems come first.
function EncounterScript.ParseExpanded(expansion, rootId)
    local parse = EncounterScript.Parse(expansion.text)
    parse.sources = expansion.sources
    parse.rootId = rootId
    parse.included = expansion.included
    local warnings = {}
    for _, w in ipairs(expansion.warnings) do
        warnings[#warnings + 1] = w
    end
    for _, w in ipairs(parse.warnings) do
        local n, rest = string.match(w, "^line (%d+): (.*)$")
        if n ~= nil then
            w = EncounterScript.LineLabel(parse, tonumber(n)) .. ": " .. rest
        end
        warnings[#warnings + 1] = w
    end
    parse.warnings = warnings
    return parse
end

--The journal keys a document's annotations by tag text, and a repeated tag
--by occurrence: the 1st [[scene]] is "scene", the 2nd "scene-1", the 3rd
--"scene-2" (MarkdownDocument:GetReferencedAnnotations). The key for the tag
--`tagText` on line `line` of `text`.
function EncounterScript.AnnotationKey(text, tagText, line)
    local needle = "[[" .. tagText .. "]]"
    local count = 0
    for i, l in ipairs(SplitLines(text)) do
        if i >= line then
            break
        end
        local from = 1
        while true do
            local s, e = string.find(l, needle, from, true)
            if s == nil then
                break
            end
            count = count + 1
            from = e + 1
        end
    end
    if count == 0 then
        return tagText
    end
    return tagText .. "-" .. count
end

function EncounterScript.Parse(text)
    local lines = SplitLines(text)
    --`delves`: the "# Delve: <Name>" sections, by EncounterScript.MatchKey
    --of their name. They are not beats -- nothing plays them in order -- an
    --option enters one with a "Delve: <Name>" line (see "Delves" below).
    local result = { beats = {}, warnings = {}, hasEncounterTag = false, delves = {} }

    local function Warn(lineIndex, fmt, ...)
        result.warnings[#result.warnings + 1] = string.format("line %d: " .. fmt, lineIndex, ...)
    end

    local beat = nil      --current beat
    local round = nil     --current round (montage)
    local entry = nil     --current entry (montage)
    local section = nil   --current section (narrative)
    local option = nil    --current option (montage entry or narrative section)
    local paragraph = {}  --accumulating prose lines
    local paragraphLine = 0
    --where scene lines go while one is being read (an entry's scene after
    --its "---", or a scripted entry's option above / below its roll); nil
    --when lines are ordinary prose.
    local sceneTarget = nil

    local function EnsureRound(lineIndex)
        if round == nil then
            round = { number = 1, line = lineIndex, entries = {}, scaling = {}, implicit = true }
            beat.rounds[#beat.rounds + 1] = round
        end
        return round
    end

    local function FlushParagraph()
        if #paragraph == 0 then
            return
        end
        local text = trim(table.concat(paragraph, "\n"))
        paragraph = {}
        if text == "" then
            return
        end
        if beat == nil then
            --prose before the first beat is ignored (a doc title, notes).
            return
        end
        if beat.kind == "narrative" then
            --"Unlock: Intelligence" turns on an optional feature of the game
            --mode. It is a line of the beat, not of an option -- the feature
            --arrives with the scene, whatever the party chooses -- so it is
            --matched before the prose branches below and never reaches them.
            local uLabel, uRest = string.match(text, "^([%a][%a \t'%-]*):%s*(.*)$")
            if uLabel ~= nil then
                local feature, wanted = EncounterScript.ParseFeatureUnlock(uLabel, uRest)
                if wanted ~= nil then
                    if feature == nil then
                        Warn(paragraphLine, "'Unlock: %s' names no feature of Encounter of the Week; ignored", tostring(wanted))
                    elseif option ~= nil then
                        Warn(option.line or paragraphLine, "'Unlock: %s' is under the option '%s'; it belongs in the section's own text (a feature is unlocked by the scene, not by a choice); ignored", feature.name, option.name)
                    else
                        local holder = section or beat
                        holder.unlocks = holder.unlocks or {}
                        holder.unlocks[#holder.unlocks + 1] = { feature = feature.key, name = feature.name, line = paragraphLine }
                    end
                    return
                end
            end
            if option ~= nil then
                option.text = cond(option.text == "", text, option.text .. "\n\n" .. text)
                return
            end
            if section ~= nil then
                local label, rest = string.match(text, "^([%a][%a \t'%-]*):%s*(.*)$")
                local mode = label ~= nil and NarrativeMode(label) or nil
                if mode ~= nil then
                    if mode ~= "prompt" then
                        section.mode = mode
                        section.modeExplicit = true
                    end
                    rest = trim(rest or "")
                    if rest ~= "" then
                        section.prompt = cond(section.prompt == "", rest, section.prompt .. "\n\n" .. rest)
                    end
                    return
                end
                section.text = cond(section.text == "", text, section.text .. "\n\n" .. text)
                return
            end
            beat.intro = cond(beat.intro == "", text, beat.intro .. "\n\n" .. text)
            return
        end
        if beat.kind == "encounter" then
            --"Label: instruction" paragraphs are setup instructions the host
            --runs before spawning the monsters; other prose is notes.
            --One instruction per LINE (adjacent lines are one paragraph).
            local lineIndex = paragraphLine
            for _, l in ipairs(SplitLines(text)) do
                local label, rest = string.match(trim(l), "^([%a][%a '%-]*):%s*(.*)$")
                if label ~= nil then
                    local instruction = EncounterScript.ParseSetupInstruction(rest)
                    if instruction == nil then
                        Warn(lineIndex, "unrecognized encounter setup instruction '%s: %s'; ignored", label, rest)
                        instruction = { kind = "unknown" }
                    end
                    instruction.label = trim(label)
                    instruction.text = trim(rest)
                    instruction.line = lineIndex
                    beat.setup[#beat.setup + 1] = instruction
                end
                lineIndex = lineIndex + 1
            end
            return
        end
        if beat.kind ~= "montage" and beat.kind ~= "delve" then
            return
        end
        if option ~= nil then
            --"Delve: Forbidden Tomb" on an option: taking the option enters
            --that delve instead of rolling a test.
            local delveName = string.match(text, "^[Dd]elve:%s*(.-)%s*$")
            if delveName ~= nil and delveName ~= "" then
                option.delve = delveName
                option.delveLine = paragraphLine
                return
            end
            option.text = cond(option.text == "", text, option.text .. "\n\n" .. text)
            return
        end
        if entry ~= nil then
            local label, rest = string.match(text, "^(%a+):%s*(.*)$")
            local key = label ~= nil and lower(label) or nil
            if label ~= nil then
                local feature = EncounterScript.ParseFeatureUnlock(label, rest)
                if feature ~= nil then
                    Warn(paragraphLine, "'Unlock: %s' only works in a narrative beat; ignored", feature.name)
                    return
                end
            end
            if key == "options" or key == "option" then
                entry.approach = cond(entry.approach == "", rest, entry.approach .. "\n\n" .. rest)
                return
            end
            if key == "consequence" or key == "consequences" then
                if entry.kind ~= "threat" then
                    Warn(paragraphLine, "Consequence: on an opportunity (%s) is ignored", entry.name)
                    return
                end
                entry.consequence = { text = rest, effects = EncounterScript.ParseEffects(rest) }
                return
            end
            if EncounterScript.IsScalingDirectiveLine(text) then
                Warn(paragraphLine, "party-size directive '%s' must sit directly under its '## Round N' heading, above the entries; ignored", trim(text))
                return
            end
            entry.description = cond(entry.description == "", text, entry.description .. "\n\n" .. text)
            return
        end
        if beat.kind == "delve" then
            --"Chest: every 1-2 obstacles" sets how often a chest turns up;
            --other prose is the delve's own notes.
            local lo, hi = string.match(lower(text), "^chest:%s*every%s+(%d+)%s*%-%s*(%d+)")
            if lo == nil then
                lo = string.match(lower(text), "^chest:%s*every%s+(%d+)")
                hi = lo
            end
            if lo ~= nil then
                lo, hi = tonumber(lo), tonumber(hi)
                if lo < 1 or hi < lo then
                    Warn(paragraphLine, "'%s' is not a usable chest interval; using every 1-2 obstacles", trim(text))
                else
                    beat.chestEvery = { lo, hi }
                end
                return
            end
            beat.intro = cond(beat.intro == "", text, beat.intro .. "\n\n" .. text)
            return
        end
        if round ~= nil then
            --directly under a "## Round N" heading: party-size directives
            --("3-5 Players: -1 Opportunity, -1 Threat"), one per LINE.
            --Anything else in the paragraph is still montage prose.
            local leftover = {}
            local lineIndex = paragraphLine
            for _, l in ipairs(SplitLines(text)) do
                local t = trim(l)
                if EncounterScript.IsScalingDirectiveLine(t) then
                    local directive = EncounterScript.ParseScalingDirective(t)
                    if directive == nil then
                        Warn(lineIndex, "party-size directive '%s' not understood; ignored (use '3-5 Players: -1 Opportunity, -1 Threat')", t)
                    else
                        directive.line = lineIndex
                        round.scaling[#round.scaling + 1] = directive
                    end
                elseif t ~= "" then
                    leftover[#leftover + 1] = t
                end
                lineIndex = lineIndex + 1
            end
            if #leftover == 0 then
                return
            end
            text = table.concat(leftover, "\n")
        end
        beat.intro = cond(beat.intro == "", text, beat.intro .. "\n\n" .. text)
    end

    local i = 1
    while i <= #lines do
        local raw = lines[i]
        local line = trim(raw)

        local h1 = string.match(line, "^#%s+(.+)$")
        local h2 = string.match(line, "^##%s+(.+)$")
        local h3 = string.match(line, "^###%s+(.+)$")
        --a longer heading matches the shorter patterns too; disambiguate.
        if h3 ~= nil then h2 = nil; h1 = nil end
        if h2 ~= nil then h1 = nil end
        if h1 == nil and h2 == nil and h3 == nil and string.match(line, "^####") then
            --deeper headings are prose
            h1, h2, h3 = nil, nil, nil
        end

        if h1 ~= nil then
            FlushParagraph()
            local title = trim(h1)
            local kind = lower(title)
            local delveName = string.match(title, "^[Dd]elve:%s*(.+)$")
            if delveName ~= nil then
                kind = "delve"
            elseif kind ~= "montage" and kind ~= "encounter" and kind ~= "narrative" then
                Warn(i, "unknown beat '%s' (expected Montage, Narrative, Encounter or Delve: <name>); ignored", title)
                kind = "unknown"
            end
            beat = { kind = kind, title = title, line = i, tags = {} }
            if kind == "montage" then
                beat.intro = ""
                beat.rounds = {}
            elseif kind == "narrative" then
                beat.intro = ""
                beat.sections = {}
            elseif kind == "encounter" then
                beat.setup = {}
            end
            if kind == "delve" then
                beat.name = trim(delveName)
                beat.intro = ""
                beat.obstacles = {}
                beat.sections = {}
                beat.chestEvery = { 1, 2 }
                local key = EncounterScript.MatchKey(beat.name)
                if result.delves[key] ~= nil then
                    Warn(i, "a second '# Delve: %s'; only the first is used", beat.name)
                else
                    result.delves[key] = beat
                end
            else
                result.beats[#result.beats + 1] = beat
            end
            round, entry, section, option = nil, nil, nil, nil
            sceneTarget = nil
        elseif h2 ~= nil then
            FlushParagraph()
            sceneTarget = nil
            local title = trim(h2)
            if beat ~= nil and beat.kind == "narrative" then
                section = {
                    name = title,
                    line = i,
                    text = "",
                    prompt = "",
                    mode = "together",
                    options = {},
                }
                --no "/" in an id: see the note on entry.id below.
                section.id = string.format("s%d-%s", #beat.sections + 1, Slug(title))
                beat.sections[#beat.sections + 1] = section
                option = nil
            elseif beat ~= nil and beat.kind == "delve" then
                entry, option = nil, nil
                local obstacleName = string.match(title, "^[Oo]bstacle:%s*(.+)$")
                local sectionKey = EncounterScript.DELVE_SECTIONS[lower(title)]
                if obstacleName ~= nil then
                    entry = {
                        kind = "obstacle",
                        name = trim(obstacleName),
                        line = i,
                        description = "",
                        approach = "",
                        options = {},
                        delve = beat.name,
                    }
                    --no "/" in an id: see the note on entry.id below.
                    entry.id = string.format("d-%s-%s", Slug(beat.name), Slug(entry.name))
                    beat.obstacles[#beat.obstacles + 1] = entry
                elseif sectionKey ~= nil then
                    --a scene of the delve itself: every line under it plays.
                    entry = {
                        kind = "delvesection",
                        section = sectionKey,
                        name = title,
                        line = i,
                        description = "",
                        approach = "",
                        options = {},
                        scripted = true,
                        sceneLines = {},
                        delve = beat.name,
                    }
                    entry.id = string.format("d-%s-%s", Slug(beat.name), sectionKey)
                    if beat.sections[sectionKey] ~= nil then
                        Warn(i, "delve '%s' already has a '## %s'; this one is ignored", beat.name, title)
                    else
                        beat.sections[sectionKey] = entry
                    end
                    sceneTarget = entry.sceneLines
                else
                    Warn(i, "'## %s' in a delve is not 'Obstacle: <name>', 'Chest', 'Continue', 'Leave' or 'Forced Out'; ignored", title)
                end
            elseif beat == nil or beat.kind ~= "montage" then
                Warn(i, "'## %s' outside a montage or narrative beat; ignored", title)
            else
                local roundNumber = string.match(lower(title), "^round%s+(%d+)$")
                local entryKind, entryName = string.match(title, "^(%a+):%s*(.+)$")
                entryKind = entryKind ~= nil and lower(entryKind) or nil
                if roundNumber ~= nil then
                    round = { number = tonumber(roundNumber), line = i, entries = {}, scaling = {} }
                    beat.rounds[#beat.rounds + 1] = round
                    entry, option = nil, nil
                elseif entryKind == "opportunity" or entryKind == "threat" then
                    EnsureRound(i)
                    --"## Opportunity: Hunter's Camp (Required)",
                    --"## Opportunity: Interrogate the Goblin (Locked)",
                    --"## Threat: The Pact (Required, Temporary)": the tags
                    --are stripped from the name (they are never part of it).
                    --(Required) is never removed by a party-size directive;
                    --(Locked) is off the board entirely until an "Unlock
                    --<name>" outcome lets it on; (Temporary) is gone at the
                    --end of the round it appeared in. A parenthesis that is
                    --not a tag is part of the name.
                    local entryTitle = trim(entryName)
                    local tags = {}
                    while true do
                        local beforeTag, tag = string.match(entryTitle, "^(.-)%s*%(([^()]*)%)%s*$")
                        if beforeTag == nil or trim(beforeTag) == "" then
                            break
                        end
                        local found, known = {}, true
                        for word in string.gmatch(tag, "[^,;]+") do
                            word = lower(trim(word))
                            if word == "required" or word == "locked" or word == "temporary" then
                                found[word] = true
                            else
                                known = false
                            end
                        end
                        if not known or next(found) == nil then
                            break
                        end
                        for word in pairs(found) do
                            tags[word] = true
                        end
                        entryTitle = trim(beforeTag)
                    end
                    entry = {
                        kind = entryKind,
                        name = entryTitle,
                        required = tags.required == true,
                        locked = tags.locked == true,
                        temporary = tags.temporary == true,
                        round = round.number,
                        line = i,
                        description = "",
                        approach = "",
                        consequence = nil,
                        options = {},
                    }
                    --NB: an id becomes a KEY in the montage document
                    --(m.vanquished / m.taken / m.expired / m.removed), and
                    --the engine builds its patch paths by joining table keys
                    --with "/" (ScriptSerialize.BuildPathToJson). A "/" inside
                    --a key is therefore read as a path separator by the
                    --server and by every other client, so the write lands
                    --nested and is invisible to everyone but the writer.
                    --Keep ids free of "/" -- Slug() already reduces the name
                    --to [a-z0-9-].
                    entry.id = string.format("r%d-%s-%s", round.number, entryKind, Slug(entry.name))
                    round.entries[#round.entries + 1] = entry
                    option = nil
                else
                    Warn(i, "'## %s' is not 'Round N', 'Opportunity: ...' or 'Threat: ...'; ignored", title)
                end
            end
        elseif h3 ~= nil then
            FlushParagraph()
            sceneTarget = nil
            local title = trim(h3)
            if beat ~= nil and beat.kind == "narrative" then
                if section == nil then
                    Warn(i, "'### %s' outside a narrative '## section'; ignored", title)
                else
                    option = { name = title, line = i, text = "", effects = {} }
                    section.options[#section.options + 1] = option
                end
            elseif entry == nil then
                Warn(i, "'### %s' outside an opportunity/threat; ignored", title)
            else
                option = { name = title, line = i, text = "", roll = nil }
                entry.options[#entry.options + 1] = option
                --in a scripted entry, what an option says before its roll
                --is the scene played once it is picked.
                if entry.scripted then
                    option.preLines = {}
                    sceneTarget = option.preLines
                end
            end
        elseif string.match(line, "^%-%-%-+$") and beat ~= nil and (beat.kind == "montage" or beat.kind == "delve") then
            --"---" ends an entry's card text and starts its scene.
            FlushParagraph()
            if entry == nil or option ~= nil then
                Warn(i, "'---' starts a scene only inside an opportunity or threat, above its first '### option'; ignored")
            else
                if entry.scripted then
                    Warn(i, "%s '%s' already has a scene; this '---' is ignored", entry.kind, entry.name)
                end
                entry.scripted = true
                entry.sceneLines = entry.sceneLines or {}
                sceneTarget = entry.sceneLines
            end
        elseif string.match(line, "^%[%[.+%]%]$") then
            --a rich-tag island on a line of its own
            FlushParagraph()
            local tagText = string.match(line, "^%[%[(.+)%]%]$")
            local tagName = lower(string.match(tagText, "^(.-):") or tagText)
            if tagName == "encounter" then
                result.hasEncounterTag = true
            end
            if beat ~= nil then
                beat.tags[#beat.tags + 1] = tagText
                --sceneLine says WHICH [[scene]] this is: its annotation lives
                --on the document the line came from (see ExpandIncludes),
                --keyed by how many of the same tag precede it there.
                if beat.kind == "montage" and tagName == "scene" and beat.sceneTag == nil then
                    beat.sceneTag = tagText
                    beat.sceneLine = i
                end
                if beat.kind == "narrative" and tagName == "scene" then
                    --inside a section it is that section's backdrop; above
                    --them all it is the beat's.
                    if section ~= nil then
                        if section.sceneTag == nil then
                            section.sceneTag = tagText
                            section.sceneLine = i
                        end
                    elseif beat.sceneTag == nil then
                        beat.sceneTag = tagText
                        beat.sceneLine = i
                    end
                end
                if tagName == "encounter" and beat.encounterTag == nil then
                    beat.encounterTag = tagText
                end
            end
        elseif string.match(line, "^|") and beat ~= nil and beat.kind == "narrative" then
            --a narrative option's rules text: one "|clause. clause" line per
            --line, the same clause grammar a montage tier line uses.
            FlushParagraph()
            local effectText = trim(string.gsub(string.match(line, "^|(.*)$") or "", "|%s*$", ""))
            if option == nil then
                Warn(i, "'|%s' is not under a '### option'; ignored", effectText)
            elseif effectText ~= "" then
                for _, effect in ipairs(EncounterScript.ParseEffects(effectText)) do
                    if effect.unrecognized then
                        Warn(i, "unrecognized effect '%s' (shown as text only)", effect.text)
                    end
                    option.effects[#option.effects + 1] = effect
                end
            end
        elseif string.match(line, "^|") then
            --a power roll block: "|Name: Attr" then 3-4 "|tier" lines
            FlushParagraph()
            local name, attr = string.match(line, "^|([^|]+): ([^|]+)$")
            local dice = attr ~= nil and string.match(trim(attr), "^(%d*[dD]%d+)$") or nil
            if name ~= nil and dice ~= nil then
                --"|Treasure: 1d6" then one "|1-2: result" row per range: a
                --table rolled on with plain dice (a delve's chest).
                local tableRoll = { name = trim(name), dice = lower(dice), rows = {} }
                local j = i + 1
                while j <= #lines do
                    local rowText = string.match(trim(lines[j]), "^|([^|]*)$")
                    if rowText == nil then
                        break
                    end
                    local lo, hi, what = string.match(trim(rowText), "^(%d+)%s*%-%s*(%d+)%s*:%s*(.*)$")
                    if lo == nil then
                        lo, what = string.match(trim(rowText), "^(%d+)%s*:%s*(.*)$")
                        hi = lo
                    end
                    if lo == nil then
                        Warn(j, "'|%s' is not a table row (use '|1-2: result' or '|3: result'); ignored", trim(rowText))
                    else
                        local row = { lo = tonumber(lo), hi = tonumber(hi), text = trim(what), line = j }
                        row.effects = EncounterScript.ParseEffects(row.text)
                        for _, effect in ipairs(row.effects) do
                            if effect.unrecognized then
                                Warn(j, "unrecognized effect '%s' (shown as text only)", effect.text)
                            end
                        end
                        tableRoll.rows[#tableRoll.rows + 1] = row
                    end
                    j = j + 1
                end
                if entry == nil or entry.section ~= "chest" then
                    Warn(i, "a dice table ('%s: %s') belongs under a delve's '## Chest'; ignored", trim(name), dice)
                elseif entry.table ~= nil then
                    Warn(i, "the chest already has a table; '%s' ignored", trim(name))
                else
                    entry.table = tableRoll
                end
                i = j - 1
            elseif name == nil then
                Warn(i, "'|' line is not a power roll header (|Name: Attr); ignored")
            else
                local tiers = {}
                local riders = {}
                local j = i + 1
                while j <= #lines do
                    local tierText = string.match(trim(lines[j]), "^|([^|]*)$")
                    if tierText == nil then
                        break
                    end
                    --"|Edge: you speak Caelian" is a rider, not a tier
                    local effect, requirementText = EncounterScript.ParseRiderLine(trim(tierText))
                    if effect ~= nil then
                        if requirementText == "" then
                            Warn(j, "rider '%s' has no requirement; ignored", trim(tierText))
                        else
                            local requirement = EncounterScript.ParseRequirement(requirementText)
                            for _, alt in ipairs(requirement.alternatives) do
                                if alt.kind == "unknown" then
                                    Warn(j, "requirement '%s' not understood (use 'you are skilled in X', 'you speak X' or 'you are a X'); never met", alt.text)
                                end
                            end
                            riders[#riders + 1] = { effect = effect, text = requirementText, requirement = requirement, line = j }
                        end
                    elseif #tiers >= 4 then
                        break
                    else
                        tiers[#tiers + 1] = trim(tierText)
                    end
                    j = j + 1
                end
                if #tiers < 3 then
                    Warn(i, "power roll '%s' has %d tier lines (need 3, optionally 4); ignored", trim(name), #tiers)
                elseif option == nil then
                    Warn(i, "power roll '%s' is not under a '### option'; ignored", trim(name))
                elseif option.roll ~= nil then
                    Warn(i, "option '%s' already has a power roll; '%s' ignored", option.name, trim(name))
                else
                    local roll = { name = trim(name), attr = trim(attr), tiers = tiers, teasers = {}, effects = {}, riders = riders }
                    for t, tierText in ipairs(tiers) do
                        local teaser, fullText = EncounterScript.SplitTeaser(tierText)
                        if teaser == "" then
                            Warn(i + t, "tier %d of '%s' has an empty teaser before '=>'; shown in full", t, trim(name))
                            teaser = nil
                        end
                        tiers[t] = fullText
                        roll.teasers[t] = teaser
                        roll.effects[t] = EncounterScript.ParseEffects(fullText)
                        for _, effect in ipairs(roll.effects[t]) do
                            if effect.unrecognized then
                                Warn(i + t, "unrecognized effect '%s' (shown as text only)", effect.text)
                            end
                        end
                    end
                    option.roll = roll
                    --and what it says after the roll plays once it lands.
                    if entry ~= nil and entry.scripted then
                        option.postLines = {}
                        sceneTarget = option.postLines
                    end
                end
                i = j - 1
            end
        elseif sceneTarget ~= nil and line ~= "" then
            --one scene step per line. The entry's own "Options:" and
            --"Consequence:" paragraphs still mean what they always did.
            local label = string.match(line, "^(%a+):")
            label = label ~= nil and lower(label) or nil
            if sceneTarget == (entry ~= nil and entry.sceneLines or nil)
                and (label == "options" or label == "option" or label == "consequence" or label == "consequences") then
                FlushParagraph()
                paragraph = { line }
                paragraphLine = i
                FlushParagraph()
            elseif option ~= nil and sceneTarget == option.preLines and string.match(line, "^[Dd]elve:%s*.+$") then
                --taking this option enters a delve (see FlushParagraph).
                option.delve = trim(string.match(line, "^[Dd]elve:%s*(.+)$"))
                option.delveLine = i
            else
                sceneTarget[#sceneTarget + 1] = { text = line, line = i }
            end
        elseif line == "" then
            FlushParagraph()
        else
            if #paragraph == 0 then
                paragraphLine = i
            end
            paragraph[#paragraph + 1] = line
        end
        i = i + 1
    end
    FlushParagraph()

    --scenes: compiled once the whole entry has been read, because speech is
    --recognized from the characters the entry brings on anywhere in it. A
    --delve's obstacles and sections are compiled the same way.
    local scripted = {}
    for _, b in ipairs(result.beats) do
        for _, e in ipairs(EncounterScript.MontageEntries(b)) do
            scripted[#scripted + 1] = e
        end
    end
    for _, d in pairs(result.delves) do
        for _, e in ipairs(d.obstacles) do
            scripted[#scripted + 1] = e
        end
        for _, e in pairs(d.sections) do
            scripted[#scripted + 1] = e
        end
    end
    do
        for _, e in ipairs(scripted) do
            if e.scripted then
                local lists = { e.sceneLines }
                for _, o in ipairs(e.options) do
                    lists[#lists + 1] = o.preLines
                    lists[#lists + 1] = o.postLines
                end
                e.actors = EncounterScript.SceneActors(lists)
                e.scene = EncounterScript.CompileScene(e.sceneLines, e.actors, "intro", Warn)
                local optionKeys = {}
                for _, o in ipairs(e.options) do
                    optionKeys[EncounterScript.MatchKey(o.name)] = true
                end
                for _, o in ipairs(e.options) do
                    o.preScene = EncounterScript.CompileScene(o.preLines, e.actors, "option", Warn)
                    o.postScene = EncounterScript.CompileScene(o.postLines, e.actors, "outcome", Warn)
                end
                --"PC chose X" has to name one of this entry's options.
                local function CheckChose(steps)
                    for _, step in ipairs(steps or {}) do
                        if step.kind == "if" then
                            for _, branch in ipairs(step.branches) do
                                local function Visit(node)
                                    if node == nil then
                                        return
                                    end
                                    if node.op == "chose" and not optionKeys[EncounterScript.MatchKey(node.name)] then
                                        Warn(step.line, "'PC chose %s' names no '### option' of %s", node.name, e.name)
                                    end
                                    Visit(node.a)
                                    Visit(node.b)
                                end
                                Visit(branch.cond)
                                CheckChose(branch.steps)
                            end
                            CheckChose(step.elseSteps)
                        end
                    end
                end
                CheckChose(e.scene)
                for _, o in ipairs(e.options) do
                    CheckChose(o.preScene)
                    CheckChose(o.postScene)
                end
            end
        end
    end

    --post-parse checks
    for _, b in ipairs(result.beats) do
        if b.kind == "montage" then
            if #b.rounds == 0 then
                Warn(b.line, "montage has no opportunities or threats")
            end
            for _, r in ipairs(b.rounds) do
                for _, d in ipairs(r.scaling or {}) do
                    for kind, n in pairs(d.removals) do
                        local pool = 0
                        for _, e in ipairs(r.entries) do
                            if e.kind == kind and not e.required and not e.locked then
                                pool = pool + 1
                            end
                        end
                        if n > pool then
                            Warn(d.line, "'%s' drops %d %s but round %d introduces only %d that may be removed", d.text, n, kind, r.number, pool)
                        end
                    end
                end
                for _, e in ipairs(r.entries) do
                    if #e.options == 0 then
                        Warn(e.line, "%s '%s' has no options", e.kind, e.name)
                    end
                    for _, o in ipairs(e.options) do
                        if o.delve ~= nil then
                            if result.delves[EncounterScript.MatchKey(o.delve)] == nil then
                                Warn(o.delveLine or o.line, "option '%s' enters the delve '%s', but there is no '# Delve: %s'", o.name, o.delve, o.delve)
                            end
                            if o.roll ~= nil then
                                Warn(o.line, "option '%s' enters a delve; its power roll is ignored", o.name)
                            end
                        elseif o.roll == nil then
                            Warn(o.line, "option '%s' has no power roll", o.name)
                        end
                    end
                    if e.kind == "threat" and e.consequence == nil then
                        Warn(e.line, "threat '%s' has no Consequence:", e.name)
                    end
                    if e.consequence ~= nil then
                        for _, effect in ipairs(e.consequence.effects) do
                            if effect.unrecognized then
                                Warn(e.line, "unrecognized consequence '%s' (shown as text only)", effect.text)
                            end
                        end
                    end
                end
            end
            --Clauses that name something else in the montage have to
            --find it: an "Unlock <name>" that names no "(Locked)" entry
            --does nothing, a locked entry nothing unlocks is a card the
            --party can never be shown, and an "Edge on <name>" that names
            --no "### option" is an edge nobody will ever get.
            local locked = {}
            local unlocks = {}
            local optionNames = {}
            for _, e in ipairs(EncounterScript.MontageEntries(b)) do
                if e.locked then
                    locked[EncounterScript.MatchKey(e.name)] = true
                end
                for _, o in ipairs(e.options) do
                    optionNames[EncounterScript.MatchKey(o.name)] = true
                end
            end
            local function CheckReferences(effects, atLine)
                for _, effect in ipairs(effects or {}) do
                    if effect.kind == "unlock" then
                        if not locked[effect.key] then
                            Warn(atLine, "'%s' names no '(Locked)' opportunity or threat of this montage", effect.text)
                        else
                            unlocks[effect.key] = true
                        end
                    elseif effect.kind == "testmod" and not optionNames[effect.key] then
                        Warn(atLine, "'%s' names no '### option' of this montage", effect.text)
                    end
                end
            end
            for _, e in ipairs(EncounterScript.MontageEntries(b)) do
                if e.consequence ~= nil then
                    CheckReferences(e.consequence.effects, e.line)
                end
                for _, o in ipairs(e.options) do
                    if o.roll ~= nil then
                        for t in ipairs(o.roll.tiers) do
                            CheckReferences(o.roll.effects[t], o.line)
                        end
                    end
                end
            end
            for _, e in ipairs(EncounterScript.MontageEntries(b)) do
                if e.locked and not unlocks[EncounterScript.MatchKey(e.name)] then
                    Warn(e.line, "%s '%s' is (Locked) but nothing unlocks it", e.kind, e.name)
                end
            end
        elseif b.kind == "narrative" then
            if #b.sections == 0 then
                Warn(b.line, "narrative beat has no '## <section>' headings")
            end
            for _, sec in ipairs(b.sections) do
                if #sec.options == 0 then
                    --text that simply appears: everyone acknowledges it.
                    sec.options[1] = { name = "Proceed", line = sec.line, text = "", effects = {}, implicit = true }
                    sec.implicitOption = true
                elseif #sec.options > 1 and not sec.modeExplicit then
                    Warn(sec.line, "section '%s' does not say 'Choose together:' or 'Choose individually:'; assuming together", sec.name)
                end
                for _, o in ipairs(sec.options) do
                    for _, effect in ipairs(o.effects or {}) do
                        if effect.kind == "unlock" or effect.kind == "testmod" then
                            Warn(o.line or sec.line, "'%s' is in a narrative beat; only a montage beat has entries and tests to name", effect.text)
                        end
                    end
                end
            end
        elseif b.kind == "encounter" and b.encounterTag == nil then
            Warn(b.line, "encounter beat has no [[encounter]] island under it")
        end
    end

    --A pool nothing unlocked is a clause that will silently do nothing: the
    --Intelligence the party earned would have nowhere to go and no screen to
    --spend it on. Warn once, naming the first clause that wants it.
    local features = EncounterScript.UnlockedFeatures(result)
    if not features.intelligence then
        local found = nil
        local function Scan(effects, line)
            for _, effect in ipairs(effects or {}) do
                if effect.kind == "intelligence" and found == nil then
                    found = { text = effect.text, line = line }
                end
            end
        end
        for _, b in ipairs(result.beats) do
            for _, sec in ipairs(b.sections or {}) do
                for _, o in ipairs(sec.options or {}) do
                    Scan(o.effects, o.line or sec.line)
                end
            end
            for _, e in ipairs(EncounterScript.MontageEntries(b)) do
                if e.consequence ~= nil then
                    Scan(e.consequence.effects, e.line)
                end
                for _, o in ipairs(e.options or {}) do
                    if o.roll ~= nil then
                        for t in ipairs(o.roll.tiers) do
                            Scan(o.roll.effects[t], o.line)
                        end
                    end
                end
            end
        end
        if found ~= nil then
            Warn(found.line or 0, "'%s' but nothing unlocks Intelligence; write 'Unlock: Intelligence' in a narrative beat or the party can never spend it", found.text)
        end
    end

    --delves: something to meet, a way to be rewarded, and tests to take.
    for _, d in pairs(result.delves) do
        if #d.obstacles == 0 then
            Warn(d.line, "delve '%s' has no '## Obstacle: ...'", d.name)
        end
        local chest = d.sections.chest
        if chest == nil then
            Warn(d.line, "delve '%s' has no '## Chest'; no treasure will turn up", d.name)
        elseif chest.table == nil then
            Warn(chest.line, "delve '%s': '## Chest' has no dice table ('|Treasure: 1d6' then '|1-2: ...' rows)", d.name)
        end
        for _, sec in pairs(d.sections) do
            if #sec.options > 0 then
                Warn(sec.line, "'## %s' of delve '%s' is a scene; its '### options' are ignored", sec.name, d.name)
            end
        end
        for _, e in ipairs(d.obstacles) do
            if #e.options == 0 then
                Warn(e.line, "obstacle '%s' has no options", e.name)
            end
            for _, o in ipairs(e.options) do
                if o.roll == nil then
                    Warn(o.line, "option '%s' has no power roll", o.name)
                end
                if o.delve ~= nil then
                    Warn(o.delveLine or o.line, "option '%s' is inside a delve already; 'Delve: %s' is ignored", o.name, o.delve)
                    o.delve = nil
                end
            end
        end
    end

    --implicit encounter: no beats at all, but an [[encounter]] island
    if #result.beats == 0 and result.hasEncounterTag then
        result.beats[1] = { kind = "encounter", title = "Encounter", line = 0, tags = { "encounter" }, setup = {}, implicit = true }
    end

    return result
end

--Every entry of a montage beat, in document order, each with its round.
function EncounterScript.MontageEntries(beat)
    local result = {}
    for _, r in ipairs((beat and beat.rounds) or {}) do
        for _, e in ipairs(r.entries) do
            result[#result + 1] = e
        end
    end
    return result
end

--The "# Delve: <Name>" a parse defines, by name (nil when there is none).
function EncounterScript.FindDelve(parse, name)
    if parse == nil or parse.delves == nil or name == nil then
        return nil
    end
    return parse.delves[EncounterScript.MatchKey(name)]
end

--One obstacle of a delve, by id.
function EncounterScript.FindObstacle(delve, obstacleId)
    for _, e in ipairs((delve and delve.obstacles) or {}) do
        if e.id == obstacleId then
            return e
        end
    end
    return nil
end

--The row of a delve chest's table a dice total lands on (nil if none).
function EncounterScript.ChestRow(tableRoll, total)
    for _, row in ipairs((tableRoll and tableRoll.rows) or {}) do
        if total >= row.lo and total <= row.hi then
            return row
        end
    end
    return nil
end

function EncounterScript.FindEntry(beat, entryId)
    for _, e in ipairs(EncounterScript.MontageEntries(beat)) do
        if e.id == entryId then
            return e
        end
    end
    return nil
end

--Entries available in a given round: everything introduced in that round
--or an earlier one (opportunities and threats both persist round to round
---- user direction 2026-09-18).
function EncounterScript.EntriesForRound(beat, roundNumber)
    local result = {}
    for _, r in ipairs((beat and beat.rounds) or {}) do
        if r.number <= roundNumber then
            for _, e in ipairs(r.entries) do
                result[#result + 1] = e
            end
        end
    end
    return result
end

--The highest round number in the montage (1 when there are no explicit
--rounds).
function EncounterScript.RoundCount(beat)
    local n = 0
    for _, r in ipairs((beat and beat.rounds) or {}) do
        if r.number > n then
            n = r.number
        end
    end
    if n == 0 then
        n = 1
    end
    return n
end

--Every section of a narrative beat, in document order.
function EncounterScript.NarrativeSections(beat)
    return (beat and beat.sections) or {}
end

function EncounterScript.FindSection(beat, sectionId)
    for _, sec in ipairs(EncounterScript.NarrativeSections(beat)) do
        if sec.id == sectionId then
            return sec
        end
    end
    return nil
end

function EncounterScript.SectionCount(beat)
    return #EncounterScript.NarrativeSections(beat)
end

--Every item and monster name the script references, for validation.
function EncounterScript.ReferencedNames(parse)
    local items, monsters = {}, {}
    local function Collect(effects)
        for _, effect in ipairs(effects or {}) do
            if effect.kind == "item" then
                items[effect.name] = true
            elseif effect.kind == "ally" then
                monsters[effect.name] = true
            end
        end
    end
    for _, b in ipairs(parse.beats or {}) do
        for _, sec in ipairs(EncounterScript.NarrativeSections(b)) do
            for _, o in ipairs(sec.options) do
                Collect(o.effects)
            end
        end
        for _, e in ipairs(EncounterScript.MontageEntries(b)) do
            if e.consequence ~= nil then
                Collect(e.consequence.effects)
            end
            for _, o in ipairs(e.options) do
                if o.roll ~= nil then
                    for _, effects in pairs(o.roll.effects) do
                        Collect(effects)
                    end
                end
            end
        end
    end
    return items, monsters
end

--Plain-text dump of a parse, for the /eotwscript command and tests.
function EncounterScript.Describe(parse)
    local out = {}
    local function line(fmt, ...)
        out[#out + 1] = string.format(fmt, ...)
    end
    for bi, b in ipairs(parse.beats or {}) do
        line("beat %d: %s (%s)%s", bi, b.title, b.kind, cond(b.implicit, " [implicit]", ""))
        if b.kind == "encounter" then
            for _, ins in ipairs(b.setup or {}) do
                if ins.kind == "placeobjects" then
                    line("  setup %s: place %d x '%s' in %s zones%s", ins.label, ins.qty, ins.object, ins.zone,
                        cond(ins.deleteOthers, ", delete the other " .. ins.zone .. " zones", ""))
                else
                    line("  setup %s: UNRECOGNIZED '%s'", ins.label, ins.text)
                end
            end
        end
        if b.kind == "narrative" then
            if b.sceneTag ~= nil then
                line("  scene: [[%s]]", b.sceneTag)
            end
            for _, u in ipairs(b.unlocks or {}) do
                line("  unlocks feature: %s", u.name)
            end
            for _, sec in ipairs(b.sections) do
                line("  section: %s  [%s] (%s)", sec.name, sec.id, sec.mode)
                for _, u in ipairs(sec.unlocks or {}) do
                    line("    unlocks feature: %s", u.name)
                end
                if sec.sceneTag ~= nil then
                    line("    scene: [[%s]]", sec.sceneTag)
                end
                if sec.prompt ~= "" then
                    line("    prompt: %s", sec.prompt)
                end
                for _, o in ipairs(sec.options) do
                    line("    option: %s%s", o.name, cond(o.implicit, " (implicit)", ""))
                    for _, effect in ipairs(o.effects) do
                        line("      - %s", EncounterScript.DescribeEffect(effect))
                    end
                end
            end
        elseif b.kind == "montage" then
            if b.sceneTag ~= nil then
                line("  scene: [[%s]]", b.sceneTag)
            end
            for _, r in ipairs(b.rounds) do
                line("  round %d%s", r.number, cond(r.implicit, " (implicit)", ""))
                for _, d in ipairs(r.scaling or {}) do
                    local parts = {}
                    for kind, n in pairs(d.removals) do
                        parts[#parts + 1] = string.format("-%d %s", n, kind)
                    end
                    table.sort(parts)
                    line("    scaling: %d%s players -> %s", d.min,
                        cond(d.max == nil, "+", cond(d.max == d.min, "", "-" .. tostring(d.max))),
                        table.concat(parts, ", "))
                end
                for _, e in ipairs(r.entries) do
                    line("    %s: %s%s%s%s  [%s]", e.kind, e.name, cond(e.required, " (required)", ""),
                        cond(e.locked, " (locked)", ""), cond(e.temporary, " (temporary)", ""), e.id)
                    if e.consequence ~= nil then
                        line("      consequence: %s", e.consequence.text)
                        for _, effect in ipairs(e.consequence.effects) do
                            line("        - %s", EncounterScript.DescribeEffect(effect))
                        end
                    end
                    for _, o in ipairs(e.options) do
                        line("      option: %s", o.name)
                        if o.roll ~= nil then
                            line("        roll: %s: %s", o.roll.name, o.roll.attr)
                            for t, tierText in ipairs(o.roll.tiers) do
                                if o.roll.teasers[t] ~= nil then
                                    line("        tier %d: [%s] => %s", t, o.roll.teasers[t], tierText)
                                else
                                    line("        tier %d: %s", t, tierText)
                                end
                                for _, effect in ipairs(o.roll.effects[t]) do
                                    line("          - %s", EncounterScript.DescribeEffect(effect))
                                end
                            end
                            for _, rider in ipairs(o.roll.riders or {}) do
                                local alts = {}
                                for _, alt in ipairs(rider.requirement.alternatives) do
                                    alts[#alts + 1] = string.format("%s=%s", alt.kind, alt.name)
                                end
                                line("        %s: %s (%s)", EncounterScript.RiderLabel(rider.effect), rider.text, table.concat(alts, " | "))
                            end
                        end
                    end
                end
            end
        end
    end
    for _, w in ipairs(parse.warnings or {}) do
        line("WARNING %s", w)
    end
    return table.concat(out, "\n")
end

--"1 surge" / "2 surges": a count with the noun it counts, correctly
--pluralized. The plural defaults to the singular with an "s" on the end;
--pass it explicitly for anything irregular. Written without cond() so the
--pure-Lua parser tests can call it with no engine globals present.
function EncounterScript.Plural(qty, singular, plural)
    if qty == 1 then
        return string.format("%d %s", qty, singular)
    end
    return string.format("%d %s", qty, plural or (singular .. "s"))
end

function EncounterScript.DescribeEffect(effect)
    if effect.kind == "item" then
        return string.format("%s gains %d x %s", cond(effect.target == "party", "every hero", "the hero"), effect.qty, effect.name)
    elseif effect.kind == "stamina" then
        return string.format("%s loses %d stamina", cond(effect.target == "party", "every hero", "the hero"), effect.qty)
    elseif effect.kind == "heal" then
        return string.format("%s heals %d stamina", cond(effect.target == "party", "every hero", "the hero"), effect.qty)
    elseif effect.kind == "temphp" then
        return string.format("%s gains %d temporary stamina", cond(effect.target == "party", "every hero", "the hero"), effect.qty)
    elseif effect.kind == "surges" then
        return string.format("%s gains %s at the start of the next combat", cond(effect.target == "party", "every hero", "the hero"), EncounterScript.Plural(effect.qty, "surge"))
    elseif effect.kind == "recovery" then
        return string.format("%s recovery value is increased by %d until the next respite", cond(effect.target == "party", "every hero's", "the hero's"), effect.qty)
    elseif effect.kind == "loserecovery" then
        return string.format("%s loses %s", cond(effect.target == "party", "every hero", "the hero"), EncounterScript.Plural(effect.qty, "recovery", "recoveries"))
    elseif effect.kind == "herotoken" then
        return string.format("the party gains %s", EncounterScript.Plural(effect.qty, "hero token"))
    elseif effect.kind == "intelligence" then
        return string.format("the party gains %s", EncounterScript.Plural(effect.qty, "Intelligence", "Intelligence"))
    elseif effect.kind == "malice" then
        return string.format("+%d malice", effect.qty)
    elseif effect.kind == "ally" then
        return string.format("%s joins the hero", effect.name)
    elseif effect.kind == "vanquish" then
        return "the threat is vanquished"
    elseif effect.kind == "initiative" then
        return EncounterScript.DescribeInitiativeOutcome(effect.outcome)
    elseif effect.kind == "nosurprise" then
        return EncounterScript.DescribeSurpriseImmunity()
    elseif effect.kind == "fairinitiative" then
        return EncounterScript.DescribeFairInitiative()
    elseif effect.kind == "knowstamina" then
        return EncounterScript.DescribeKnowStamina(effect.keyword)
    elseif effect.kind == "revealzones" then
        return EncounterScript.DescribeRevealZones(effect.zone)
    elseif effect.kind == "unlock" then
        return string.format("unlock '%s'", effect.name)
    elseif effect.kind == "testmod" then
        return string.format("%s on '%s'", lower(EncounterScript.RiderLabel(effect.effect)), effect.name)
    end
    return string.format("narrative%s: %s", cond(effect.unrecognized, " (unrecognized)", ""), effect.text)
end

--The player-facing line for a stamina reveal: "The party knows the Stamina
--of Goblins".
function EncounterScript.DescribeKnowStamina(keyword)
    keyword = tostring(keyword or "")
    local shown = string.upper(string.sub(keyword, 1, 1)) .. string.sub(keyword, 2) .. "s"
    return string.format("The party knows the Stamina of %s", shown)
end

--The player-facing line for an initiative outcome (also what the stage
--shows in the applied-effects list).
--
--`immune` is "the party already has surprise immunity" (`you cannot be
--surprised` landed earlier in this montage). A "surprised" clause under
--immunity still hands the initiative to the monsters, but no hero takes
--the condition -- and announcing it as "the heroes will begin the
--encounter surprised" told the party the exact opposite of what was about
--to happen (reported live 2026-09-20). Say both halves instead.
function EncounterScript.DescribeInitiativeOutcome(outcome, immune)
    if outcome == "surprised" then
        if immune then
            return "The heroes will lose initiative, but they cannot be surprised"
        end
        return "The heroes will begin the encounter surprised"
    elseif outcome == "surprise" then
        return "The heroes will surprise the enemy"
    elseif outcome == "win" then
        return "The heroes will win initiative"
    elseif outcome == "lose" then
        return "The heroes will lose initiative"
    end
    return string.format("initiative: %s", tostring(outcome))
end

--The player-facing line for the surprise-immunity boon.
function EncounterScript.DescribeSurpriseImmunity()
    return "The heroes cannot be surprised"
end
