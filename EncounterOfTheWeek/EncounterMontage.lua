--Encounter of the Week: the montage runtime.
--
--Runs a "# Montage" beat of the map's script (EncounterScript.lua): heroes
--take turns approaching opportunities and threats, roll the option they
--chose, and the tier's effects are applied. Design: EncounterOfTheWeek.md,
--"Encounter scripts: montage beats before combat".
--
--Authority model: the HOST is the single writer of montage.* state, from the
--map script's host tick (EncounterMontage.HostTick). Players only ever stamp
--montage.requests[userid] (EncounterMontage.SendRequest) and the host tick
--validates and applies them in order. The one thing a player's client does
--on its own is ROLL: the owner of the acting hero shows the roll dialog
--(EncounterMontage.ClientTick) and reports the tier back as a request.
--
--The shared document ("eotwscript", this codemod's namespace):
--  data.beat     = current beat index into the parsed script (host-stamped)
--  data.montage  = {
--    beatIndex, round, phase = "rounds"|"consequences"|"done",
--    acted = { [heroCharid] = true },       -- this round
--    taken = { [entryId] = true },          -- opportunities consumed
--    vanquished = { [entryId] = true },     -- threats resolved
--    unlocked = { [entryKey] = round },     -- "(Locked)" entries an "Unlock
--                                              <name>" outcome has let onto
--                                              the board, and the round it
--                                              happened in (keyed by
--                                              EncounterScript.MatchKey, not
--                                              by entry id)
--    expired = { [entryId] = true },        -- "(Temporary)" entries the
--                                              round they appeared in has
--                                              carried off
--    testmods = { [optionKey] = { { effect = "edge"|"doubleedge"|"bane"|
--                                   "doublebane", entryName, at }, ... } },
--                                           -- standing edges/banes an
--                                              "Edge on <option>" outcome
--                                              put on another test, for
--                                              WHOEVER takes it
--    turn = nil | { seq, userid, heroid, entryId,
--                   status = "scene"|"choosing"|"rolling"|"assist"|"assisting"|"resolved",
--                   scene = { id, part = "intro"|"option"|"outcome",
--                             steps = { { kind = "narrate"|"say", text, speaker,
--                                         side = "left"|"right", lang, garbled,
--                                         cast = { { name, monster }, ... },
--                                         emotes = nil | { { name, side, emote }, ... } }, ... },
--                             cast },   -- the lines playing on the stage (see
--                                          BuildScenePart); `cast` is who is on
--                                          stage once the part has played
--                   sceneAfter = "choosing"|"rolling"|"resolve",
--                                           -- where a "scene" turn goes when its
--                                              lines have all been read
--                   pendingTier, resolveUserid,  -- an outcome scene's tier, applied
--                                                   once the scene has played
--                   delve = nil | { name, entryName, depth, sinceChest, chestAt,
--                                   used = { [obstacleId] = true }, obstacleId,
--                                   chests, applied = { line, ... } },
--                                           -- a "Delve: <Name>" option was taken:
--                                              the whole delve is this turn (see
--                                              "delves (host side)"). While
--                                              obstacleId is set, the turn's entry
--                                              and option are the OBSTACLE's.
--                   status also "chest" (the chest's dice roll is out) and
--                   "delvechoice" (press deeper or turn back) inside a delve.
--                   optionIndex, rollSeq, tier, total, natural, applied = {...}, resolvedAt,
--                   attrid, skillid,        -- what the acting hero rolled with
--                   baseTier, baseTotal,    -- the test's own result, before an assist
--                   assistOpenedAt,         -- when the assist window opened
--                   assist = nil | { userid, heroid, heroName, skillid, skillName,
--                                    status = "rolling"|"resolved", rollSeq,
--                                    tier, total, natural, outcome } },
--                   -- "assist": the test landed below tier 3 and a hero with an
--                      applicable skill may still lend a hand (see ASSIST_TIERS).
--    consequences = { entryId, ... }, consequenceIndex, lastApplied = {...},
--    requests = { [userid] = { seq, kind, ... } }, handled = { [userid] = seq },
--    log = { { round, heroid, heroName, entryId, entryName, optionName, tier, applied }, ... },
--          (a passed turn logs { round, passed = true, heroid, heroName, entryId, entryName })
--    seq = n,
--  }
--  data.montageScene = nil | { id, index }
--                  -- how far through the playing scene (turn.scene.id) the
--                     party has read. The one key a PLAYER writes directly
--                     (EncounterMontage.AdvanceScene): only the acting hero's
--                     player advances it, and a round trip through the host
--                     for every line would make the dialogue sluggish. The
--                     host only reads it, to move the turn on once the last
--                     line has been read.
--  data.allies   = { [heroCharid] = { charid, ... } }  -- monsters that joined a hero
--  data.items    = { [heroCharid] = { { itemid, name, qty }, ... } }
--                  -- gear the montage granted, in the order it was granted
--                     (a repeat grant of the same item bumps qty in place).
--                     Shown as the icon strip beside the hero's stage card.
--  data.initiative = nil | { outcome = "win"|"lose"|"surprise"|"surprised"|"even", entryName, at }
--                  -- "even" is a fair roll that a clause explicitly asked
--                     for; the encounter beat treats it like no decision
--                  -- how the next encounter's initiative is decided (montage clause)
--  data.noSurprise = nil | { entryName, at }
--                  -- "You cannot be surprised": the party is immune to the
--                     Surprised condition in the next encounter (it still
--                     loses the initiative if the montage says so).
--  data.surges   = nil | { [heroCharid] = n }
--                  -- surges banked by "at the start of the next combat you
--                     gain N surges", paid out (and cleared) by
--                     ApplyPendingCombatBoons when combat starts.
--  data.zoneSetup, data.revealZones, data.zonesRevealed
--                  -- the encounter's zone setup (placed traps) and the
--                     "Reveal Traps" banked/applied reveals; see
--                     EncounterZones.lua.

local mod = dmhub.GetModLoading()

EncounterMontage = rawget(_G, "EncounterMontage") or {}

local DOC_ID = "eotwscript"
local DIALOG_ID = "eotwmontage"

--A resolved turn never blocks the next one: it stays on screen only until
--another hero approaches an entry (or the round rolls over), so the party
--is never made to wait out a timer on a result they have already read.
--how long the finished montage (its last consequence) stays on screen
--before the beat ends and the stage hides.
local DONE_LINGER_SECONDS = 6
--how long the assist window stays open before the host takes the test's
--own result. A backstop only -- the acting player can close it at once --
--so an absent party cannot wedge the montage.
local ASSIST_WINDOW_SECONDS = 30
--and how long a claimed assist may sit unrolled (a client that closed the
--dialog without cancelling, or went away) before the slot is handed back.
local ASSIST_ROLL_SECONDS = 90

--The fixed tier table of an assist roll (user direction 2026-09-18). It is
--not authored: every assist, whatever the test, offers the same three
--outcomes.
local ASSIST_TIERS = {
    "The test has a bane on it.",
    "The test has an edge on it.",
    "The test has a double edge on it.",
}
--tier -> what it does to the test it is assisting.
local ASSIST_OUTCOMES = { "bane", "edge", "doubleedge" }

EncounterMontage.ASSIST_TIERS = ASSIST_TIERS

--- the document ------------------------------------------------------------

function EncounterMontage.GetDoc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

function EncounterMontage.DocPath()
    return mod:GetDocumentPath(DOC_ID)
end

--The live montage state, or nil when no montage is running.
function EncounterMontage.GetState()
    local m = nil
    pcall(function() m = mod:GetDocumentSnapshot(DOC_ID).data.montage end)
    if type(m) ~= "table" then
        return nil
    end
    return m
end

--The items this hero has been granted so far this montage, in grant order:
--{ { itemid, name, qty }, ... }.
function EncounterMontage.GetItems(heroid)
    local result = {}
    pcall(function()
        local items = mod:GetDocumentSnapshot(DOC_ID).data.items
        if type(items) == "table" and type(items[heroid]) == "table" then
            for _, entry in ipairs(items[heroid]) do
                if type(entry) == "table" and entry.itemid ~= nil then
                    result[#result + 1] = { itemid = entry.itemid, name = entry.name, qty = entry.qty or 1 }
                end
            end
        end
    end)
    return result
end

--- optional features + the Intelligence pool ---------------------------------

--A feature of the game mode a script turned on for itself with
--"Unlock: <Feature>" in a narrative beat (EncounterScript.FEATURES). Off
--unless the week asks for it, so a script that never mentions Intelligence
--plays exactly as it did before the feature existed.
function EncounterMontage.FeatureUnlocked(feature)
    local on = false
    pcall(function()
        local unlocked = mod:GetDocumentSnapshot(DOC_ID).data.unlocked
        on = type(unlocked) == "table" and unlocked[feature] ~= nil
    end)
    return on
end

--Host, inside an OPEN change on the script document: turn a feature on.
--Returns true the first time, false when it was already on (so the caller
--only announces it once).
function EncounterMontage.UnlockFeature(doc, feature, sourceName)
    if doc == nil or feature == nil then
        return false
    end
    doc.data.unlocked = doc.data.unlocked or {}
    if doc.data.unlocked[feature] ~= nil then
        return false
    end
    local record = EncounterScript.FEATURES[feature]
    doc.data.unlocked[feature] = {
        name = (record ~= nil and record.name) or feature,
        entryName = sourceName,
        at = dmhub.serverTime,
    }
    return true
end

--How bright the feature-unlock blink is right now, 0..1. While the stage is
--explaining a newly unlocked feature, the pool it is about blinks a white
--rectangle in the strip (EncounterOfTheWeekHud) so the party can see which
--number the words mean. Only the pool blinks -- the explanation itself sits
--still, or it reads as something to press.
function EncounterMontage.FeatureBlinkAlpha()
    return 0.2 + 0.8 * ((math.sin(dmhub.Time() * 2 * math.pi / 0.9) + 1) / 2)
end

--The party's shared Intelligence pool: what they have worked out about the
--ground and the enemy, spent on the Tactical Preparation screen when combat
--comes. Lives at the TOP level of the script document (like initiative)
--because it spans every beat.
function EncounterMontage.GetIntelligence()
    local n = 0
    pcall(function() n = tonumber(mod:GetDocumentSnapshot(DOC_ID).data.intelligence) or 0 end)
    return n
end

--The pool's change history, in the shape gui.StatsHistoryTooltip wants
--(newest last), so the strip's cell reads like the malice and hero-token
--cells beside it.
function EncounterMontage.GetIntelligenceHistory()
    local result = {}
    pcall(function()
        for _, entry in ipairs(mod:GetDocumentSnapshot(DOC_ID).data.intelligenceLog or {}) do
            --the log stores a `dmhub.serverTime` (SECONDS) in `at`; the
            --tooltip wants the human `when` string StatHistory hands it for
            --malice and hero tokens, or the line reads "... by Someone nil".
            --Not DescribeServerTimestamp: that one takes the milliseconds
            --ServerTimestamp() returns and reads seconds as the 1970 epoch.
            local when = "pending"
            if type(entry.at) == "number" then
                when = DescribeSecondsAgo(math.max(0, (dmhub.serverTime or entry.at) - entry.at))
            end
            result[#result + 1] = {
                value = entry.value,
                who = entry.who,
                note = entry.note,
                color = entry.color or "#ccccccff",
                when = when,
            }
        end
    end)
    return result
end

function EncounterMontage.GetAllies(heroid)
    local result = {}
    pcall(function()
        local allies = mod:GetDocumentSnapshot(DOC_ID).data.allies
        if type(allies) == "table" and type(allies[heroid]) == "table" then
            for _, charid in ipairs(allies[heroid]) do
                result[#result + 1] = charid
            end
        end
    end)
    return result
end

--- the script --------------------------------------------------------------

--Cache of the current map's parsed script, keyed by a signature of every
--document it could be built from (see ScriptSignature): the text is only
--re-expanded and re-parsed when one of them actually changes.
local m_scriptCache = nil

local function DocumentText(doc)
    local text = ""
    pcall(function() text = doc:GetTextContent() or "" end)
    return text
end

local function IsMarkdown(doc)
    return type(doc) == "table" and doc.typeName == "MarkdownDocument"
end

--Resolve a sub-document link in a map's script (EncounterScript.ExpandIncludes'
--`resolve`). A document filed under the same map wins over one of the same
--name elsewhere in the journal, so two weeks can both have a "Mysterious
--Cottage" without crossing wires; anything else goes through the journal's
--own CustomDocument.ResolveLink, exactly what clicking the link opens.
function EncounterMontage.ResolveScriptInclude(target, mapid)
    local docsTable = dmhub.GetTable("documents") or {}
    local key = string.lower(target)
    local bare = string.match(key, "^document:(.+)$") or key
    local function Found(docid, doc)
        return { id = docid, name = doc.description or docid, text = DocumentText(doc) }
    end

    if IsMarkdown(docsTable[bare]) and not docsTable[bare].hidden then
        return Found(bare, docsTable[bare])
    end
    if mapid ~= nil then
        local bestid = nil
        for docid, doc in unhidden_pairs(docsTable) do
            if IsMarkdown(doc) and string.lower(doc.description or "") == bare
                and CustomDocument.IsDocInAccessibleRoot(doc, { [mapid] = true })
                and (bestid == nil or docid < bestid) then
                bestid = docid
            end
        end
        if bestid ~= nil then
            return Found(bestid, docsTable[bestid])
        end
    end

    local resolved = nil
    pcall(function() resolved = CustomDocument.ResolveLink(target) end)
    if resolved == nil then
        return nil, "names no journal document"
    end
    if IsMarkdown(resolved) then
        for docid, doc in pairs(docsTable) do
            if doc == resolved then
                return Found(docid, doc)
            end
        end
        local id = nil
        pcall(function() id = resolved.id end)
        if id ~= nil then
            return Found(id, resolved)
        end
    end
    --a monster, a PDF, a map, a web page: a link, not a sub-document.
    return nil, nil
end

--Expand and parse one document as a script (its sub-documents spliced in).
--Returns { docid, doc, parse, text, explicit }; parse.included lists the
--documents it pulled in.
function EncounterMontage.LoadScript(docid, mapid)
    local doc = (dmhub.GetTable("documents") or {})[docid]
    if doc == nil then
        return nil
    end
    local expansion = EncounterScript.ExpandIncludes(
        { id = docid, name = doc.description or docid, text = DocumentText(doc) },
        function(target) return EncounterMontage.ResolveScriptInclude(target, mapid) end)
    local parse = EncounterScript.ParseExpanded(expansion, docid)
    local explicit = #parse.beats > 0 and not parse.beats[1].implicit
    return { docid = docid, doc = doc, parse = parse, text = expansion.text, explicit = explicit }
end

--Everything a map's script could have been built from: every candidate
--document plus every document the last parse included (which may live
--outside the map's folder), by id, name and text length.
local function ScriptSignature(candidates, included)
    local docsTable = dmhub.GetTable("documents") or {}
    local parts = {}
    local seen = {}
    local function Add(docid, doc)
        if seen[docid] then
            return
        end
        seen[docid] = true
        if doc == nil then
            parts[#parts + 1] = docid .. "=missing"
        else
            parts[#parts + 1] = string.format("%s=%s:%d", docid, tostring(doc.description), #DocumentText(doc))
        end
    end
    for _, c in ipairs(candidates) do
        Add(c.docid, c.doc)
    end
    local extra = {}
    for docid in pairs(included or {}) do
        extra[#extra + 1] = docid
    end
    table.sort(extra)
    for _, docid in ipairs(extra) do
        Add(docid, docsTable[docid])
    end
    return table.concat(parts, "|")
end

--Find the map's script: the markdown document filed under the encounter
--map's journal folder (the same rule FindMapEncounter uses), with its
--sub-documents spliced in, parsed. A document that another one includes is
--a part of that script, never a script of its own. When several qualify,
--the first (by name) that declares beats wins. A map with only an
--info-bubble encounter and no document gets one implicit encounter beat, so
--a week authored the old way plays exactly as before.
--Returns { docid, doc, parse, text } or a script with no beats.
function EncounterMontage.FindMapScript(force)
    local mapid = game.currentMapId
    local docsTable = dmhub.GetTable("documents") or {}
    local candidates = {}
    for docid, doc in unhidden_pairs(docsTable) do
        if doc.typeName == "MarkdownDocument" and CustomDocument.IsDocInAccessibleRoot(doc, { [mapid] = true }) then
            candidates[#candidates + 1] = { docid = docid, doc = doc }
        end
    end
    table.sort(candidates, function(a, b)
        local na, nb = a.doc.description or "", b.doc.description or ""
        if na ~= nb then
            return na < nb
        end
        return a.docid < b.docid
    end)

    if m_scriptCache ~= nil and not force and m_scriptCache.docid ~= nil and m_scriptCache.mapid == mapid
        and m_scriptCache.signature == ScriptSignature(candidates, m_scriptCache.allIncluded) then
        if m_scriptCache.docid ~= nil then
            m_scriptCache.doc = docsTable[m_scriptCache.docid] or m_scriptCache.doc
        end
        return m_scriptCache
    end

    local loaded = {}
    local allIncluded = {}
    for _, c in ipairs(candidates) do
        local script = EncounterMontage.LoadScript(c.docid, mapid)
        loaded[#loaded + 1] = script
        for docid in pairs(script ~= nil and script.parse.included or {}) do
            allIncluded[docid] = true
        end
    end

    local best = nil
    for _, script in ipairs(loaded) do
        if script ~= nil and not allIncluded[script.docid] and #script.parse.beats > 0 then
            if best == nil or (script.explicit and not best.explicit) then
                best = script
                if script.explicit then
                    break
                end
            end
        end
    end

    if best == nil then
        --no document script: an info-bubble encounter is still an encounter.
        local entry = nil
        local eotw = rawget(_G, "EncounterOfTheWeekGame")
        if eotw ~= nil and eotw.FindMapEncounter ~= nil then
            pcall(function() entry = eotw.FindMapEncounter() end)
        end
        local beats = {}
        if entry ~= nil then
            beats[1] = { kind = "encounter", title = "Encounter", line = 0, tags = { "encounter" }, implicit = true }
        end
        best = { docid = nil, doc = nil, parse = { beats = beats, warnings = {}, hasEncounterTag = entry ~= nil }, text = "" }
    end
    best.mapid = mapid
    best.allIncluded = allIncluded
    best.signature = ScriptSignature(candidates, allIncluded)
    m_scriptCache = best
    return best
end

--The first montage beat's scene image (a RichScene annotation's coverart),
--or nil. `beat` is anything with a sceneTag and sceneLine (a beat, or a
--narrative section). The annotation is read from the document that line
--came from -- a sub-document keeps its own [[scene]] islands -- under the
--journal's key for it (a repeated tag is "scene-1", "scene-2", ...).
function EncounterMontage.SceneImage(script, beat)
    if script == nil or script.doc == nil or beat == nil or beat.sceneTag == nil then
        return nil
    end
    local image = nil
    pcall(function()
        local doc = script.doc
        local key = beat.sceneTag
        local src = beat.sceneLine ~= nil and script.parse.sources ~= nil and script.parse.sources[beat.sceneLine] or nil
        if src ~= nil then
            doc = (dmhub.GetTable("documents") or {})[src.docid] or doc
            --the stage asks every frame it rebuilds; the key only changes
            --with the text, and a text change makes a new script.
            script.sceneKeys = script.sceneKeys or {}
            key = script.sceneKeys[beat.sceneLine]
            if key == nil then
                key = EncounterScript.AnnotationKey(DocumentText(doc), beat.sceneTag, src.line)
                script.sceneKeys[beat.sceneLine] = key
            end
        end
        local annotations = doc:try_get("annotations")
        local tag = annotations ~= nil and (annotations[key] or annotations[beat.sceneTag]) or nil
        if tag ~= nil and tag.typeName == "RichScene" then
            local img = tag.image
            if type(img) == "string" and img ~= "" then
                image = img
            end
        end
    end)
    return image
end

--The montage beat the state is running, from the current map's script.
function EncounterMontage.CurrentBeat()
    local m = EncounterMontage.GetState()
    if m == nil then
        return nil, nil
    end
    local script = EncounterMontage.FindMapScript()
    local beat = script.parse.beats[m.beatIndex or 0]
    if beat == nil or beat.kind ~= "montage" then
        return nil, script
    end
    return beat, script
end

--The delve a turn is in (its "# Delve:" definition), or nil.
function EncounterMontage.TurnDelve(t)
    if t == nil or t.delve == nil then
        return nil
    end
    local script = EncounterMontage.FindMapScript()
    return EncounterScript.FindDelve(script ~= nil and script.parse or nil, t.delve.name)
end

--The entry a turn is playing: the opportunity or threat itself, or -- inside
--a delve -- the obstacle the hero is facing. Its options are the ones on
--offer, rolled and resolved.
function EncounterMontage.TurnEntry(beat, t)
    if t == nil then
        return nil
    end
    if t.delve ~= nil and t.delve.obstacleId ~= nil then
        return EncounterScript.FindObstacle(EncounterMontage.TurnDelve(t), t.delve.obstacleId)
    end
    return EncounterScript.FindEntry(beat, t.entryId)
end

--- heroes ------------------------------------------------------------------

--A hero whose player never typed a name still has to label its card and its
--"X approaches Y" lines with something.
function EncounterMontage.HeroDisplayName(tok)
    local name = nil
    pcall(function() name = tok.name end)
    if name == nil or name == "" then
        return "Unnamed Hero"
    end
    return name
end

--Every hero in the party, sorted by name: { charid, token, name, ownerId }.
--
--Enumerated exactly the way combat entry does it (GatherCombatSides in
--EncounterOfTheWeek.lua): every token on the map whose properties IsHero.
--NOT Party.GetPlayerCharacters, which silently drops any token with a blank
--name -- an unnamed hero fought in the encounter but was missing from the
--montage and the HUD hero strip (report QKG5YTWG).
function EncounterMontage.Heroes()
    local result = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if tok ~= nil and tok.valid and tok.properties ~= nil then
            local isHero = false
            pcall(function() isHero = tok.properties:IsHero() end)
            if isHero then
                result[#result + 1] = {
                    charid = tok.charid,
                    token = tok,
                    name = EncounterMontage.HeroDisplayName(tok),
                    ownerId = tok.ownerId,
                }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.charid < b.charid
    end)
    return result
end

--May this user drive this hero in the montage? Direct ownership, or a
--party-owned hero (the authoring game's pregens), or the Director when the
--interface is forced on for development.
local function UserControlsHero(userid, heroEntry)
    if heroEntry == nil then
        return false
    end
    local owner = heroEntry.ownerId
    if owner == userid or owner == "PARTY" then
        return true
    end
    return false
end

--Party-size scaling: a "3-5 Players: -1 Opportunity" line under a round
--heading drops entries at random. The draw is made ONCE, by the host, when
--the party has arrived (m.removed, set by EncounterMontage.RollRemovals);
--a removed entry simply never exists as far as anyone can see -- it is
--never shown, never approachable, and never mentioned.
function EncounterMontage.EntryRemoved(m, entry)
    if m == nil or entry == nil then
        return false
    end
    return (m.removed or {})[entry.id] == true
end

--A "## Opportunity: Interrogate the Goblin (Locked)" entry is off the
--board entirely -- never shown, never approachable, and a locked threat
--delivers no consequence -- until another outcome's "Unlock <name>"
--clause lets it on. The unlocks are keyed by name
--(EncounterScript.MatchKey), not by entry id, so an author does not have
--to copy the heading letter for letter; they live in the per-beat montage
--state, so "/eotwmontage reset" locks everything again.
function EncounterMontage.EntryUnlocked(m, entry)
    if entry == nil or not entry.locked then
        return true
    end
    if m == nil then
        return false
    end
    return (m.unlocked or {})[EncounterScript.MatchKey(entry.name)] ~= nil
end

--The round this entry actually came onto the board in: the one that
--declares it, or -- for a "(Locked)" entry unlocked later -- the round the
--unlock landed in, whichever is later. This is the round a "(Temporary)"
--entry expires at the end of.
function EncounterMontage.EntryAppearRound(m, entry)
    local round = entry ~= nil and entry.round or 1
    if entry == nil or not entry.locked or m == nil then
        return round
    end
    --older state wrote `true` here rather than the round; fall back to the
    --declared round, which is right for everything but a late unlock.
    local at = tonumber((m.unlocked or {})[EncounterScript.MatchKey(entry.name)])
    if at ~= nil and at > round then
        return at
    end
    return round
end

--A "(Temporary)" entry that the round it appeared in has now carried off.
--It is gone for good: never shown, never approachable, and a threat has
--already delivered its consequence (ExpireTemporaryEntries).
function EncounterMontage.EntryExpired(m, entry)
    if m == nil or entry == nil then
        return false
    end
    return (m.expired or {})[entry.id] == true
end

--Is this entry hidden from the board right now? Removed, still locked, or
--introduced by a round whose directives have not been rolled yet -- until
--the draw is made a card that is about to be removed must not flash up
--first.
function EncounterMontage.EntryHidden(m, beat, entry)
    if EncounterMontage.EntryRemoved(m, entry) then
        return true
    end
    if not EncounterMontage.EntryUnlocked(m, entry) then
        return true
    end
    if EncounterMontage.EntryExpired(m, entry) then
        return true
    end
    if m ~= nil and m.removed == nil and EncounterScript.RoundHasScaling(beat, entry.round) then
        return true
    end
    return false
end

--Is this entry open for an approach in the given state?
function EncounterMontage.EntryAvailable(m, entry)
    if entry == nil or m == nil then
        return false
    end
    if entry.round > (m.round or 1) then
        return false
    end
    if EncounterMontage.EntryRemoved(m, entry) then
        return false
    end
    if not EncounterMontage.EntryUnlocked(m, entry) then
        return false
    end
    if EncounterMontage.EntryExpired(m, entry) then
        return false
    end
    if entry.kind == "opportunity" then
        return not ((m.taken or {})[entry.id] == true)
    end
    return not ((m.vanquished or {})[entry.id] == true)
end

--Is the floor free for the next approach? No turn at all, or one whose
--result is already in -- a resolved turn is shown, not waited on.
function EncounterMontage.TurnOver(m)
    return m ~= nil and (m.turn == nil or m.turn.status == "resolved")
end

--Can the local user drag this hero right now? (UI gate; the host re-checks.)
function EncounterMontage.LocalUserCanAct(heroid)
    local m = EncounterMontage.GetState()
    if m == nil or m.phase ~= "rounds" or not EncounterMontage.TurnOver(m) then
        return false
    end
    if (m.acted or {})[heroid] then
        return false
    end
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil or not tok.valid then
        return false
    end
    local mine = false
    pcall(function() mine = tok.canControlAsUser end)
    if mine == nil then
        pcall(function() mine = tok.canControl end)
    end
    return mine == true
end

--- assisting a test ---------------------------------------------------------
--
--A test that lands below tier 3 can still be helped: another hero who is
--skilled in one of the skills the test lists -- and whose skill the acting
--hero is not already using for their own Skilled bonus -- may assist. They
--roll the same characteristic the test used, with their own modifier and an
--automatic Skilled +2, on the fixed ASSIST_TIERS table, and it costs them
--their turn this round whatever it rolls.

--The skills an option's power roll lists, as skill ids.
function EncounterMontage.OptionSkills(option)
    if option == nil or option.roll == nil then
        return {}
    end
    local ok, _, skills = pcall(EncounterScript.ParseAttr, option.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
    if not ok or skills == nil then
        return {}
    end
    return skills
end

--- riders ------------------------------------------------------------------
--A test's riders ("|Allow: you are skilled in Magic", "|Edge: you speak
--Caelian") are weighed against the FACTS of the hero taking it. This is
--the one place those facts are read off a creature; the grammar and the
--weighing are pure (EncounterScript.EvaluateRiders), so the host's gate,
--the roll launch and the stage all agree.

--What a hero is, for rider requirements (skills, languages, class /
--subclass / ancestry), read off the creature by core (TestRiders).
function EncounterMontage.HeroFacts(charid)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid or tok.properties == nil then
        return { skill = {}, language = {}, kindred = {} }
    end
    return TestRiders.CreatureFacts(tok.properties)
end

--The standing edges and banes an earlier outcome put on this option's
--test ("Edge on Capture Them"), in the order they were granted. Unlike a
--rider they are not weighed against anybody: whoever takes the test gets
--them. Matched by option NAME, so two entries that both call an option
--"Ask for Aid" share the grant -- which is why names should be distinct
--when that is not wanted.
function EncounterMontage.OptionTestMods(m, option)
    if option == nil or option.name == nil then
        return {}
    end
    m = m or EncounterMontage.GetState()
    if m == nil then
        return {}
    end
    return (m.testmods or {})[EncounterScript.MatchKey(option.name)] or {}
end

--A granted edge/bane dressed up as an applied rider, so everything that
--already reads a verdict -- the roll dialog's modifier chips, the boon
--and bane counts -- picks it up with no special case.
local function GrantedAsApplied(granted)
    local why = "the party earned it"
    if granted.entryName ~= nil and granted.entryName ~= "" then
        why = string.format("the party earned it at %s", granted.entryName)
    end
    return {
        rider = { effect = granted.effect, text = why, granted = true },
        why = why,
    }
end

--How an option's riders fall for a hero (EncounterScript.EvaluateRiders
--result), with any standing edges and banes from the montage folded in as
--applied riders. Nil when the option has neither.
function EncounterMontage.RiderVerdict(charid, option)
    local riders = (option ~= nil and option.roll ~= nil and option.roll.riders) or {}
    local granted = EncounterMontage.OptionTestMods(nil, option)
    if #riders == 0 and #granted == 0 then
        return nil
    end
    --Declared with a type instead of initialized to nil: the checker would
    --otherwise infer `nil` from the declaration and flag every field read
    --below, since the pcall closure is what actually fills it in.
    ---@type table
    local verdict
    local ok, err = pcall(function()
        verdict = EncounterScript.EvaluateRiders(riders, EncounterMontage.HeroFacts(charid))
    end)
    if not ok then
        printf("EotW montage: rider verdict failed: %s", tostring(err))
        return nil
    end
    for _, g in ipairs(granted) do
        local applied = GrantedAsApplied(g)
        verdict.applied[#verdict.applied + 1] = applied
        local boons = EncounterScript.RiderBoons(g.effect)
        if boons > 0 then
            verdict.boons = verdict.boons + boons
        else
            verdict.banes = verdict.banes - boons
        end
    end
    return verdict
end

--The names of the riders a hero does not meet, for a refusal message.
function EncounterMontage.DescribeUnmet(verdict)
    local parts = {}
    for _, rider in ipairs((verdict or {}).unmet or {}) do
        if rider.effect == "allow" then
            parts[#parts + 1] = rider.text
        end
    end
    return table.concat(parts, "; ")
end

--The skill this hero could assist the option's test with: one the roll
--lists, that the hero is trained in, and that the acting hero is not
--already using. Returns skillid, skillName, or nil.
function EncounterMontage.AssistSkillFor(charid, option, usedSkillId)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid or tok.properties == nil then
        return nil
    end
    local skillTable = dmhub.GetTable(Skill.tableName) or {}
    for _, skillid in ipairs(EncounterMontage.OptionSkills(option)) do
        if skillid ~= usedSkillId then
            local skillInfo = skillTable[skillid]
            local trained = false
            if skillInfo ~= nil then
                pcall(function() trained = tok.properties:ProficientInSkill(skillInfo) end)
            end
            if trained then
                return skillid, skillInfo.name
            end
        end
    end
    return nil
end

--Every hero who could assist the turn in flight: { charid, skillid,
--skillName }, in Heroes() order. Empty unless a turn is waiting on an
--assist. Used by the host (to decide whether to open the window at all)
--and by the stage (to badge the cards).
function EncounterMontage.EligibleAssistants(m, beat, heroes)
    local result = {}
    local t = m ~= nil and m.turn or nil
    if t == nil or beat == nil then
        return result
    end
    if t.status ~= "assist" and t.status ~= "rolling" then
        return result
    end
    local entry = EncounterMontage.TurnEntry(beat, t)
    local option = entry ~= nil and entry.options[t.optionIndex or 0] or nil
    if option == nil or option.roll == nil then
        return result
    end
    for _, hero in ipairs(heroes or EncounterMontage.Heroes()) do
        if hero.charid ~= t.heroid and not (m.acted or {})[hero.charid] then
            local skillid, skillName = EncounterMontage.AssistSkillFor(hero.charid, option, t.skillid)
            if skillid ~= nil then
                result[#result + 1] = { charid = hero.charid, name = hero.name, skillid = skillid, skillName = skillName }
            end
        end
    end
    return result
end

--Can the local user drag this hero into the assist slot right now? (UI
--gate; the host re-checks.)
function EncounterMontage.LocalUserCanAssist(heroid)
    local m = EncounterMontage.GetState()
    if m == nil or m.phase ~= "rounds" or m.turn == nil or m.turn.status ~= "assist" then
        return false
    end
    if m.turn.heroid == heroid or (m.acted or {})[heroid] then
        return false
    end
    local beat = EncounterMontage.CurrentBeat()
    if beat == nil then
        return false
    end
    for _, candidate in ipairs(EncounterMontage.EligibleAssistants(m, beat)) do
        if candidate.charid == heroid then
            local tok = dmhub.GetCharacterById(heroid)
            if tok == nil or not tok.valid then
                return false
            end
            local mine = false
            pcall(function() mine = tok.canControlAsUser end)
            if mine == nil then
                pcall(function() mine = tok.canControl end)
            end
            return mine == true
        end
    end
    return false
end

--Apply an assist outcome to the test's own result. Draw Steel: an edge is
--+2 on the roll, a bane -2, and a double edge shifts the tier up by one.
--(RollUtils.DiceResultToTier's own thresholds, 12 and 17, re-applied here
--because the dice are already on the table.)
function EncounterMontage.ApplyAssistToTier(outcome, baseTier, baseTotal)
    local total = tonumber(baseTotal)
    local tier = tonumber(baseTier) or 1
    if outcome == "doubleedge" then
        tier = tier + 1
    elseif total ~= nil then
        total = total + cond(outcome == "bane", -2, 2)
        if total >= 17 then
            tier = 3
        elseif total >= 12 then
            tier = 2
        else
            tier = 1
        end
    end
    if tier > 3 then
        tier = 3
    elseif tier < 1 then
        tier = 1
    end
    return tier, total
end

--- requests (player side) --------------------------------------------------

--Stamp a request for the host: {seq, kind, ...args}. Each user has one
--slot; a newer request replaces an unhandled older one.
function EncounterMontage.SendRequest(kind, args)
    local userid = dmhub.loginUserid
    local doc = EncounterMontage.GetDoc()
    if doc.data.montage == nil then
        return false
    end
    doc:BeginChange()
    local m = doc.data.montage
    m.requests = m.requests or {}
    local prev = m.requests[userid]
    local req = { seq = ((prev ~= nil and prev.seq) or 0) + 1, kind = kind, time = dmhub.serverTime }
    for k, v in pairs(args or {}) do
        req[k] = v
    end
    m.requests[userid] = req
    doc:CompleteChange("Montage request: " .. tostring(kind), { undoable = false })
    return true
end

--Which line of the playing scene the party is on (1-based; one past the
--last line once it has all been read), or nil when no scene is playing.
function EncounterMontage.SceneCursor(m)
    local t = m ~= nil and m.turn or nil
    local scene = t ~= nil and t.status == "scene" and t.scene or nil
    if scene == nil then
        return nil
    end
    local cursor = EncounterMontage.GetDoc().data.montageScene
    if type(cursor) == "table" and cursor.id == scene.id then
        return tonumber(cursor.index) or 1
    end
    return 1
end

--May the local user turn the scene's page? Only the player of the hero on
--stage paces it.
function EncounterMontage.LocalUserPacesScene(m)
    local t = m ~= nil and m.turn or nil
    return t ~= nil and t.status == "scene" and t.userid == dmhub.loginUserid
end

--The acting hero's player has finished reading the line on screen.
function EncounterMontage.AdvanceScene()
    local m = EncounterMontage.GetState()
    if not EncounterMontage.LocalUserPacesScene(m) then
        return false
    end
    local index = EncounterMontage.SceneCursor(m)
    local scene = m.turn.scene
    if index == nil or index > #(scene.steps or {}) then
        return false
    end
    local doc = EncounterMontage.GetDoc()
    doc:BeginChange()
    doc.data.montageScene = { id = scene.id, index = index + 1 }
    doc:CompleteChange("Montage scene: next line", { undoable = false })
    return true
end

--- effects (host side) -----------------------------------------------------

local function NameMatches(a, b)
    return string.lower(string.gsub(a or "", "^%s*(.-)%s*$", "%1")) == string.lower(string.gsub(b or "", "^%s*(.-)%s*$", "%1"))
end

--Item by name from the gear table: exact (case-insensitive) match first,
--then the singular of a trailing "s". Hidden rows lose to visible ones.
function EncounterMontage.FindGear(name)
    local t = dmhub.GetTable("tbl_Gear") or {}
    local candidates = { name }
    if string.match(name or "", "s$") then
        candidates[#candidates + 1] = string.sub(name, 1, #name - 1)
    end
    for _, candidate in ipairs(candidates) do
        local hiddenMatch = nil
        for id, item in pairs(t) do
            if NameMatches(item.name, candidate) then
                local hidden = false
                pcall(function() hidden = item:try_get("hidden", false) == true end)
                if not hidden then
                    return id, item
                end
                hiddenMatch = hiddenMatch or { id = id, item = item }
            end
        end
        if hiddenMatch ~= nil then
            return hiddenMatch.id, hiddenMatch.item
        end
    end
    return nil
end

--Bestiary entry by name; a visible entry beats a hidden duplicate.
function EncounterMontage.FindMonster(name)
    local hiddenMatch = nil
    for id, asset in pairs(assets.monsters or {}) do
        if NameMatches(asset.name, name) then
            if not asset.hidden then
                return id, asset
            end
            hiddenMatch = hiddenMatch or { id = id, asset = asset }
        end
    end
    if hiddenMatch ~= nil then
        return hiddenMatch.id, hiddenMatch.asset
    end
    return nil
end

--A free tile for a new ally next to its hero: the nearest free Start-zone
--tile (the party is confined there before combat), else a ring search
--around the hero.
local function FreeTileNear(heroToken)
    local loc = heroToken.loc
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw ~= nil and eotw.FreeStartTileNear ~= nil then
        local tile = nil
        pcall(function() tile = eotw.FreeStartTileNear(loc) end)
        if tile ~= nil then
            return tile
        end
    end
    for radius = 1, 4 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local candidate = core.Loc { x = loc.x + dx, y = loc.y + dy, floorIndex = game.currentFloorIndex }
                    local occupied = true
                    pcall(function() occupied = game.GetTokensAtLoc(candidate) ~= nil end)
                    if not occupied then
                        return candidate
                    end
                end
            end
        end
    end
    return loc
end

local function GrantItem(token, itemid, itemName, qty)
    token:ModifyProperties{
        description = string.format("Montage: gain %s", itemName),
        undoable = false,
        execute = function()
            local props = token.properties
            local inventory = props:try_get("inventory", {})
            local current = 0
            if inventory[itemid] ~= nil and type(inventory[itemid].quantity) == "number" then
                current = inventory[itemid].quantity
            end
            props:SetItemQuantity(itemid, current + qty)
        end,
    }
end

--Remember a granted item on the script document, so the montage stage can
--show the hero's haul beside their card. Granting the same item again bumps
--the quantity in place rather than adding a second icon. Must be called
--inside the document's open change (ApplyEffects always is).
local function RecordItem(doc, heroid, itemid, itemName, qty)
    if doc == nil or heroid == nil or itemid == nil then
        return
    end
    doc.data.items = doc.data.items or {}
    doc.data.items[heroid] = doc.data.items[heroid] or {}
    local list = doc.data.items[heroid]
    for i, entry in ipairs(list) do
        if entry.itemid == itemid then
            list[i] = { itemid = itemid, name = itemName, qty = (entry.qty or 1) + qty }
            return
        end
    end
    list[#list + 1] = { itemid = itemid, name = itemName, qty = qty }
end

--The recorded haul entry for one item, or nil.
local function FindRecordedItem(doc, heroid, itemid)
    local items = doc ~= nil and doc.data.items or nil
    if type(items) ~= "table" or type(items[heroid]) ~= "table" then
        return nil
    end
    for _, entry in ipairs(items[heroid]) do
        if type(entry) == "table" and entry.itemid == itemid then
            return entry
        end
    end
    return nil
end

--Take `qty` of an item off a hero's recorded haul; the entry goes when it
--hits zero. Same change-scope rule as RecordItem.
local function UnrecordItem(doc, heroid, itemid, qty)
    local items = doc ~= nil and doc.data.items or nil
    if type(items) ~= "table" or type(items[heroid]) ~= "table" then
        return
    end
    local list = items[heroid]
    for i, entry in ipairs(list) do
        if type(entry) == "table" and entry.itemid == itemid then
            local left = (entry.qty or 1) - qty
            if left > 0 then
                list[i] = { itemid = itemid, name = entry.name, qty = left }
            else
                table.remove(list, i)
            end
            return
        end
    end
end

--How many of an item a token really carries right now.
local function InventoryQuantity(token, itemid)
    local qty = 0
    pcall(function()
        local inventory = token.properties:try_get("inventory", {})
        if inventory[itemid] ~= nil and type(inventory[itemid].quantity) == "number" then
            qty = inventory[itemid].quantity
        end
    end)
    return qty
end

local function LoseStamina(token, amount, source)
    token:ModifyProperties{
        description = string.format("Montage: lose %d stamina", amount),
        undoable = false,
        execute = function()
            local props = token.properties
            local ok = pcall(function()
                props:InflictDamageInstance(amount, "untyped", {}, source, {})
            end)
            if not ok then
                --fallback: plain stamina loss, clamped at the kill threshold.
                local taken = props:try_get("damage_taken", 0) + amount
                local max = 0
                pcall(function() max = props:MaxHitpoints() end)
                if max > 0 and taken > max then
                    taken = max
                end
                props.damage_taken = taken
            end
        end,
    }
end

local function HealStamina(token, amount, note)
    token:ModifyProperties{
        description = string.format("Montage: heal %d stamina", amount),
        undoable = false,
        execute = function()
            token.properties:Heal(amount, note)
        end,
    }
end

--Draw Steel temporary Stamina does not stack: a new grant only helps if it
--is larger than what the hero already has.
local function GrantTemporaryStamina(token, amount, note)
    token:ModifyProperties{
        description = string.format("Montage: gain %d temporary stamina", amount),
        undoable = false,
        execute = function()
            local props = token.properties
            local current = 0
            pcall(function() current = props:TemporaryHitpoints() or 0 end)
            if amount > current then
                props:SetTemporaryHitpoints(amount, note, {})
            end
        end,
    }
end

local function GrantSurges(token, amount, note)
    local surgeid = CharacterResource.nameToId["Surges"]
    if surgeid == nil then
        return false
    end
    --a surge-sharing summon banks on its summoner; operate on whoever holds
    --the pool so the mutation lands inside that token's ModifyProperties.
    local recipient = token
    pcall(function()
        local summoner = token.properties:GetSurgeSharingSummonerToken()
        if summoner ~= nil then
            recipient = summoner
        end
    end)
    recipient:ModifyProperties{
        description = string.format("Montage: gain %s", EncounterScript.Plural(amount, "surge")),
        undoable = false,
        execute = function()
            recipient.properties:AddUnboundedResource(surgeid, amount, note)
        end,
    }
    return true
end

--"You lose a recovery": the recovery is taken off the hero's long-rest
--pool and nothing is given back -- this is a cost, not Draw Steel's
--recovery SPEND, so there is no healing. ConsumeResource routes to a
--Bloodbound Band partner when the hero's own pool is empty. A hero with no
--recoveries left loses nothing and carries no debt. Returns how many were
--actually taken.
local function LoseRecoveries(token, count, note)
    count = math.floor(count or 0)
    if count <= 0 then
        return 0
    end
    local available = 0
    pcall(function() available = token.properties:RecoveriesAvailableToSpend() or 0 end)
    local losing = math.min(count, available)
    if losing <= 0 then
        return 0
    end
    token:ModifyProperties{
        description = string.format("Montage: lose %s", EncounterScript.Plural(losing, "recovery", "recoveries")),
        undoable = false,
        execute = function()
            token.properties:ConsumeResource(CharacterResource.recoveryResourceId, "long", losing, note)
        end,
    }
    return losing
end

--The ongoing effect that carries a "your Recovery Value is increased by N"
--boon. One asset per value, created in the game's own ongoing-effect table
--the first time that value is granted and reused for every later grant (so a
--week that hands out +2 three times adds one row, not three).
local function EnsureRecoveryBoonEffect(amount)
    local name = string.format("Montage Boon: Recovery Value +%d", amount)
    local t = dmhub.GetTable("characterOngoingEffects") or {}
    for id, effect in pairs(t) do
        if NameMatches(effect.name, name) then
            return id
        end
    end
    local effect = CharacterOngoingEffect.Create{
        name = name,
        source = "Montage",
        description = string.format("Your Recovery Value is increased by %d.", amount),
        custom = true,
    }
    effect.modifiers = {
        CharacterModifier.new{
            behavior = "attribute",
            attribute = "recoveryvalue",
            operation = "add",
            value = amount,
            name = name,
            source = "Montage",
            guid = dmhub.GenerateGuid(),
        },
    }
    return dmhub.SetAndUploadTableItem("characterOngoingEffects", effect)
end

local function GrantRecoveryBoon(token, amount)
    local effectid = EnsureRecoveryBoonEffect(amount)
    if effectid == nil then
        return false
    end
    --creature:ApplyOngoingEffect reads the table through GetTableCached,
    --whose snapshot only refreshes on the "refreshTables" event -- a row
    --uploaded moments ago is not in it yet and the apply silently no-ops.
    --EncounterMontage.PrepareBoonAssets creates these at the start of the
    --beat so this is normally long since true; say so rather than report a
    --grant that did not happen.
    if GetTableCached("characterOngoingEffects")[effectid] == nil then
        printf("EotW montage: '%s' is not visible to the rules engine yet; the boon was not applied", effectid)
        return false
    end
    token:ModifyProperties{
        description = string.format("Montage: Recovery Value +%d", amount),
        undoable = false,
        execute = function()
            token.properties:ApplyOngoingEffect(effectid, "until_rest", nil, {})
        end,
    }
    return true
end

--Spawn a bestiary monster as the acting hero's ally: owned by the hero's
--player, in the party, tagged eotwAllyOf = the hero. Returns the token.
--Host, once per montage beat: create every ongoing-effect asset the beat's
--boons will need, before any hero can roll for one. The rules engine reads
--the ongoing-effect table through a cache that only refreshes on the
--"refreshTables" event, so an asset uploaded in the same breath as the grant
--is invisible to creature:ApplyOngoingEffect. Doing it at the start of the
--beat puts thousands of frames between the upload and the first grant.
function EncounterMontage.PrepareBoonAssets(beat)
    local amounts = {}
    local function Collect(effects)
        for _, effect in ipairs(effects or {}) do
            if effect.kind == "recovery" then
                amounts[effect.qty] = true
            end
        end
    end
    for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
        if entry.consequence ~= nil then
            Collect(entry.consequence.effects)
        end
        for _, option in ipairs(entry.options) do
            if option.roll ~= nil then
                for _, effects in pairs(option.roll.effects) do
                    Collect(effects)
                end
            end
        end
    end
    if next(amounts) == nil then
        return
    end

    ElevateToHostPermissions()
    local ok, err = pcall(function()
        for amount, _ in pairs(amounts) do
            EnsureRecoveryBoonEffect(amount)
        end
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW montage: boon asset setup failed: %s", tostring(err))
    end
end

local function SpawnAlly(monsterid, heroEntry, userid)
    local loc = FreeTileNear(heroEntry.token)
    local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true })
    if token == nil then
        return nil
    end
    pcall(function() token.properties:OnCreateFromBestiary(token, dmhub.GenerateGuid()) end)
    --partyId FIRST: its setter force-writes ownerId = "PARTY", so ownership
    --must be written after it (see ClaimPastedHero in EncounterOfTheWeek.lua).
    pcall(function() token.partyId = GetDefaultPartyID() end)
    local owner = userid
    if heroEntry.ownerId ~= nil and heroEntry.ownerId ~= "PARTY" then
        owner = heroEntry.ownerId
    end
    if owner ~= nil and owner ~= "PARTY" then
        token.ownerId = owner
    end
    token.properties.eotwAllyOf = heroEntry.charid
    token:UploadToken("Montage: ally joins")
    return token
end

--Put the Surprised condition on (or take it off) every hero on the map,
--right now. The montage announces surprise the moment the clause lands, so
--the players SEE it arrive rather than discovering it -- or not -- when the
--Draw Steel banner resolves minutes later. Duration "eoe": it survives the
--rest of the montage and the narrative beat, and creature:EndCombat clears
--it when the encounter ends, exactly like the Prepare Combat dialog's "All
--Surprised" slider. Caller must already hold host permissions.
--Allies spawned later, and the enemy side, are still handled at combat
--start by StartEncounterCombat -- this is the hero half only.
local function SetHeroesSurprised(on, description)
    local surprisedCondition = CharacterCondition.conditionsByName["surprised"]
    if surprisedCondition == nil then
        return
    end
    for _, hero in ipairs(EncounterMontage.Heroes()) do
        local token = hero.token
        if token.valid then
            token:ModifyProperties{
                description = description,
                undoable = false,
                execute = function()
                    token.properties:InflictCondition(surprisedCondition.id, {
                        force = true,
                        duration = "eoe",
                        purge = not on,
                    })
                end,
            }
        end
    end
end

--The source line an effect records on damage and resource changes:
--"Montage: Dangerous Beasts", "Narrative: The Crossroads".
local function SourceLabel(ctx)
    return string.format("%s: %s", ctx.source or "Montage", tostring(ctx.entryName))
end

--Apply a list of effects (a tier's clauses, a Consequence:, or a narrative
--option's rules text) on the host.
--ctx = { heroEntry (nil for consequences), heroEntries (several heroes --
--a narrative option taken by more than one, takes precedence over
--heroEntry), userid, entryName, source ("Montage"/"Narrative"), montage
--(the state table being mutated), entryId, doc (the script document, inside
--an open change, for effects that outlive the beat) }. Returns the list of
--human-readable results and the list of ally charids spawned.
function EncounterMontage.ApplyEffects(effects, ctx)
    local applied = {}
    local newAllies = {}
    local heroes = EncounterMontage.Heroes()
    local function Targets(effect)
        if effect.target == "party" then
            return heroes
        end
        if ctx.heroEntries ~= nil and #ctx.heroEntries > 0 then
            return ctx.heroEntries
        end
        if ctx.heroEntry ~= nil then
            return { ctx.heroEntry }
        end
        return {}
    end
    --"Kira", "Kira and Brann", "Kira, Brann and Osk".
    local function TargetNames(names)
        if #names <= 1 then
            return names[1] or ""
        end
        return string.format("%s and %s", table.concat(names, ", ", 1, #names - 1), names[#names])
    end
    --the same list plus a verb that agrees with it.
    local function Subject(names, singular, plural)
        return string.format("%s %s", TargetNames(names), cond(#names > 1, plural, singular))
    end

    --The prose clauses of a line are joined back into one entry as they are
    --applied (see the "narrative" branch below): runIndex is the entry the
    --run is being built in, runText its text without the sentence-ending
    --punctuation, runSep the punctuation the last clause added to it ended
    --on.
    local runIndex, runText, runSep = nil, nil, ""

    ElevateToHostPermissions()
    local ok, err = pcall(function()
        for _, effect in ipairs(effects or {}) do
            --a clause the author wrapped in "{...}" is applied exactly as
            --written, but the party is never told: whatever it appends to
            --`applied` below is taken back off at the end of this pass, so
            --no turn summary or montage log line carries it.
            local appliedFrom = #applied + 1
            if effect.kind == "item" then
                local itemid, item = EncounterMontage.FindGear(effect.name)
                if itemid == nil then
                    applied[#applied + 1] = string.format("Unknown item '%s'", effect.name)
                else
                    local names = {}
                    for _, target in ipairs(Targets(effect)) do
                        local grantOk = pcall(GrantItem, target.token, itemid, item.name, effect.qty)
                        if grantOk then
                            names[#names + 1] = target.name
                            pcall(RecordItem, ctx.doc, target.charid, itemid, item.name, effect.qty)
                        end
                    end
                    if effect.target == "party" then
                        applied[#applied + 1] = string.format("Every hero gains %d x %s", effect.qty, item.name)
                    elseif #names > 0 then
                        applied[#applied + 1] = string.format("%s %d x %s", Subject(names, "gains", "gain"), effect.qty, item.name)
                    end
                end
            elseif effect.kind == "stamina" then
                local names = {}
                for _, target in ipairs(Targets(effect)) do
                    local dmgOk = pcall(LoseStamina, target.token, effect.qty, SourceLabel(ctx))
                    if dmgOk then
                        names[#names + 1] = target.name
                    end
                end
                if effect.target == "party" then
                    applied[#applied + 1] = string.format("Every hero loses %d Stamina", effect.qty)
                elseif #names > 0 then
                    applied[#applied + 1] = string.format("%s %d Stamina", Subject(names, "loses", "lose"), effect.qty)
                end
            elseif effect.kind == "heal" then
                local names = {}
                for _, target in ipairs(Targets(effect)) do
                    if pcall(HealStamina, target.token, effect.qty, SourceLabel(ctx)) then
                        names[#names + 1] = target.name
                    end
                end
                if effect.target == "party" then
                    applied[#applied + 1] = string.format("Every hero heals %d Stamina", effect.qty)
                elseif #names > 0 then
                    applied[#applied + 1] = string.format("%s %d Stamina", Subject(names, "heals", "heal"), effect.qty)
                end
            elseif effect.kind == "temphp" then
                local names = {}
                for _, target in ipairs(Targets(effect)) do
                    if pcall(GrantTemporaryStamina, target.token, effect.qty, SourceLabel(ctx)) then
                        names[#names + 1] = target.name
                    end
                end
                if effect.target == "party" then
                    applied[#applied + 1] = string.format("Every hero gains %d Temporary Stamina", effect.qty)
                elseif #names > 0 then
                    applied[#applied + 1] = string.format("%s %d Temporary Stamina", Subject(names, "gains", "gain"), effect.qty)
                end
            elseif effect.kind == "recovery" then
                local names = {}
                for _, target in ipairs(Targets(effect)) do
                    local grantOk, granted = pcall(GrantRecoveryBoon, target.token, effect.qty)
                    if grantOk and granted then
                        names[#names + 1] = target.name
                    end
                end
                if effect.target == "party" then
                    applied[#applied + 1] = string.format("Every hero's Recovery Value +%d until the next respite", effect.qty)
                elseif #names > 0 then
                    applied[#applied + 1] = string.format("%s: Recovery Value +%d until the next respite", TargetNames(names), effect.qty)
                end
            elseif effect.kind == "loserecovery" then
                --a hero with fewer recoveries than the clause asks for
                --loses what they have, so report what each hero actually
                --lost rather than what was asked of them.
                local byAmount = {}
                local amounts = {}
                local nothing = {}
                for _, target in ipairs(Targets(effect)) do
                    local callOk, lost = pcall(LoseRecoveries, target.token, effect.qty, SourceLabel(ctx))
                    lost = cond(callOk, lost or 0, 0)
                    if lost > 0 then
                        if byAmount[lost] == nil then
                            byAmount[lost] = {}
                            amounts[#amounts + 1] = lost
                        end
                        table.insert(byAmount[lost], target.name)
                    else
                        nothing[#nothing + 1] = target.name
                    end
                end
                table.sort(amounts)
                for _, amount in ipairs(amounts) do
                    local lostText = EncounterScript.Plural(amount, "Recovery", "Recoveries")
                    if effect.target == "party" and #amounts == 1 and #nothing == 0 then
                        applied[#applied + 1] = string.format("Every hero loses %s", lostText)
                    else
                        applied[#applied + 1] = string.format("%s %s", Subject(byAmount[amount], "loses", "lose"), lostText)
                    end
                end
                if #nothing > 0 then
                    applied[#applied + 1] = string.format("%s no Recoveries left to lose", Subject(nothing, "has", "have"))
                end
            elseif effect.kind == "surges" then
                --banked on the document, not granted now: surges are a
                --combat-scoped resource, and StartEncounterCombat pays them
                --out once the fight has begun (ApplyPendingCombatBoons).
                local names = {}
                if ctx.doc ~= nil then
                    ctx.doc.data.surges = ctx.doc.data.surges or {}
                    for _, target in ipairs(Targets(effect)) do
                        ctx.doc.data.surges[target.charid] = (ctx.doc.data.surges[target.charid] or 0) + effect.qty
                        names[#names + 1] = target.name
                    end
                end
                if effect.target == "party" then
                    applied[#applied + 1] = string.format("Every hero begins the encounter with %s", EncounterScript.Plural(effect.qty, "surge"))
                elseif #names > 0 then
                    applied[#applied + 1] = string.format("%s the encounter with %s", Subject(names, "begins", "begin"), EncounterScript.Plural(effect.qty, "surge"))
                end
            elseif effect.kind == "herotoken" then
                --one pool for the whole party, like malice.
                local before = 0
                pcall(function() before = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) or 0 end)
                pcall(function()
                    CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, before + effect.qty,
                        SourceLabel(ctx))
                end)
                applied[#applied + 1] = string.format("+%s", EncounterScript.Plural(effect.qty, "Hero Token"))
            elseif effect.kind == "intelligence" then
                --the party's shared Intelligence pool. It is ours, not a
                --CharacterResource, so it is kept on the script document
                --with a history of its own for the strip's tooltip.
                if ctx.doc == nil then
                    printf("EotW montage: no script document open; '%s' not applied", tostring(effect.text))
                else
                    local before = tonumber(ctx.doc.data.intelligence) or 0
                    ctx.doc.data.intelligence = before + effect.qty
                    local log = ctx.doc.data.intelligenceLog or {}
                    log[#log + 1] = {
                        value = before + effect.qty,
                        amount = effect.qty,
                        who = ctx.entryName or "Encounter of the Week",
                        note = SourceLabel(ctx),
                        at = dmhub.serverTime,
                    }
                    ctx.doc.data.intelligenceLog = log
                    applied[#applied + 1] = string.format("+%s", EncounterScript.Plural(effect.qty, "Intelligence", "Intelligence"))
                end
            elseif effect.kind == "malice" then
                local before = CharacterResource.GetMalice() or 0
                CharacterResource.SetMalice(before + effect.qty, SourceLabel(ctx))
                applied[#applied + 1] = string.format("+%d Malice", effect.qty)
            elseif effect.kind == "ally" then
                local monsterid, asset = EncounterMontage.FindMonster(effect.name)
                local joined = Targets(effect)
                if monsterid == nil then
                    applied[#applied + 1] = string.format("Unknown monster '%s'", effect.name)
                elseif #joined == 0 then
                    applied[#applied + 1] = string.format("%s cannot join: no hero", asset.name)
                else
                    --one ally per hero the clause landed on (a narrative
                    --option several heroes took brings several allies).
                    local names = {}
                    for _, target in ipairs(joined) do
                        local token = SpawnAlly(monsterid, target, ctx.userid)
                        if token ~= nil then
                            newAllies[#newAllies + 1] = token.charid
                            names[#names + 1] = target.name
                        end
                    end
                    if #names == 0 then
                        applied[#applied + 1] = string.format("%s could not be placed", asset.name)
                    else
                        applied[#applied + 1] = string.format("%s joins %s", asset.name, TargetNames(names))
                    end
                end
            elseif effect.kind == "vanquish" then
                if ctx.montage ~= nil and ctx.entryId ~= nil then
                    ctx.montage.vanquished = ctx.montage.vanquished or {}
                    ctx.montage.vanquished[ctx.entryId] = true
                end
                applied[#applied + 1] = "The threat is vanquished"
            elseif effect.kind == "initiative" then
                --read BEFORE anything is written: whether the party was
                --already warded decides both the condition and the wording.
                local surpriseImmune = ctx.doc ~= nil and ctx.doc.data.noSurprise ~= nil
                --remembered at the top level of the script document (not in
                --montage.*, which is reset per beat) so the encounter beat
                --can read it when it starts combat. Last one applied wins
                --for WHO GOES FIRST -- but surprise is sticky (below): a
                --later "you lose initiative" must not quietly cancel an
                --earlier "you begin the encounter surprised", which is what
                --a montage that hands out both consequences used to do.
                if ctx.doc ~= nil then
                    ctx.doc.data.initiative = {
                        outcome = effect.outcome,
                        entryName = ctx.entryName,
                        at = dmhub.serverTime,
                    }
                    local side = nil
                    if effect.outcome == "surprised" then
                        side = "party"
                    elseif effect.outcome == "surprise" then
                        side = "enemy"
                    end
                    if side ~= nil then
                        ctx.doc.data.surprised = ctx.doc.data.surprised or {}
                        ctx.doc.data.surprised[side] = {
                            entryName = ctx.entryName,
                            at = dmhub.serverTime,
                        }
                        --the heroes take it NOW, so the montage's "you begin
                        --the encounter surprised" is something the party can
                        --see on their tokens the moment it is announced.
                        --(The enemy side does not exist yet -- its monsters
                        --are spawned for the encounter -- so "surprise" is
                        --still applied at combat start.)
                        if side == "party" and not surpriseImmune then
                            SetHeroesSurprised(true, "Montage: surprised")
                        end
                    end
                end
                --under "you cannot be surprised" the line has to say so: the
                --party still loses the die, but announcing a bare "the
                --heroes will begin the encounter surprised" over the top of
                --their own immunity read as the immunity having been
                --forgotten (reported live 2026-09-20).
                applied[#applied + 1] = EncounterScript.DescribeInitiativeOutcome(effect.outcome, surpriseImmune and effect.outcome == "surprised")
            elseif effect.kind == "nosurprise" then
                --party-wide and permanent for the run, whoever earned it.
                --Like initiative it lives at the TOP level of the document
                --so it survives the per-beat rebuild of montage.*. It does
                --NOT override the initiative outcome: a "surprised" result
                --still loses the die, it just withholds the condition.
                if ctx.doc ~= nil then
                    ctx.doc.data.noSurprise = {
                        entryName = ctx.entryName,
                        at = dmhub.serverTime,
                    }
                end
                --immunity can be earned AFTER the surprise landed, so lift
                --the condition the earlier clause already applied.
                SetHeroesSurprised(false, "Montage: cannot be surprised")
                applied[#applied + 1] = EncounterScript.DescribeSurpriseImmunity()
            elseif effect.kind == "fairinitiative" then
                --"The encounter begins with a fair roll": take back what
                --the montage decided AGAINST the party and nothing else.
                --The party's Surprised flag goes (and the condition comes
                --off the heroes who are already wearing it), and a "lose"
                --or "surprised" outcome is replaced with "even", which the
                --encounter beat reads as "no immediate result, roll for
                --it". An enemy the montage surprised stays surprised -- so
                --the heroes still go first if they had already earned that
                ---- and a "win" outcome is left standing.
                if ctx.doc ~= nil then
                    local surprised = ctx.doc.data.surprised
                    if type(surprised) == "table" and surprised.party ~= nil then
                        if surprised.enemy ~= nil then
                            ctx.doc.data.surprised = { enemy = surprised.enemy }
                        else
                            ctx.doc.data.surprised = nil
                        end
                    end
                    local init = ctx.doc.data.initiative
                    local outcome = type(init) == "table" and init.outcome or nil
                    if outcome == nil or outcome == "lose" or outcome == "surprised" then
                        ctx.doc.data.initiative = {
                            outcome = "even",
                            entryName = ctx.entryName,
                            at = dmhub.serverTime,
                        }
                    else
                        printf("EotW montage: a fair roll was called for, but '%s' already stands", tostring(outcome))
                    end
                end
                --the heroes may already be wearing the condition from an
                --earlier clause; it comes off now, not at combat start.
                SetHeroesSurprised(false, "Montage: a fair roll")
                applied[#applied + 1] = EncounterScript.DescribeFairInitiative()
            elseif effect.kind == "knowstamina" then
                --monster intelligence: the exact stamina of every monster
                --carrying the keyword, now and later. Lives in the shared
                --monsterKnowledge document (Draw Steel Core Rules), not in
                --eotwscript, so the Monster Info dialog and the token stamina
                --bars pick it up the same way as any other reveal.
                local knowledge = rawget(_G, "MonsterKnowledge")
                if knowledge ~= nil and knowledge.RevealStaminaForKeyword ~= nil then
                    knowledge.RevealStaminaForKeyword(effect.keyword, SourceLabel(ctx))
                    applied[#applied + 1] = EncounterScript.DescribeKnowStamina(effect.keyword)
                else
                    printf("EotW montage: MonsterKnowledge is unavailable; %s not applied", tostring(effect.text))
                end
            elseif effect.kind == "revealzones" then
                --"Reveal Traps during the next combat": banked on the
                --document, applied by the encounter beat right before the
                --stage dissolves (EncounterZones.ApplyPendingReveals), when
                --the players' zone overlay is switched on too.
                local zones = rawget(_G, "EncounterZones")
                if zones ~= nil and ctx.doc ~= nil then
                    zones.BankReveal(ctx.doc, effect.zone, ctx.entryName)
                    applied[#applied + 1] = EncounterScript.DescribeRevealZones(effect.zone)
                else
                    printf("EotW montage: EncounterZones is unavailable; %s not applied", tostring(effect.text))
                end
            elseif effect.kind == "unlock" then
                --a "(Locked)" entry joins the board: at once if the round
                --it is declared in has been reached, otherwise when that
                --round comes. Recorded in the per-beat montage state, so
                --it only means anything inside a montage (a narrative
                --beat passes no `montage`, and the parser warns about an
                --unlock written there).
                if ctx.montage ~= nil then
                    ctx.montage.unlocked = ctx.montage.unlocked or {}
                    --the ROUND, not just a flag: a "(Locked, Temporary)"
                    --entry expires at the end of the round it appeared in,
                    --which is this one when the unlock comes late.
                    ctx.montage.unlocked[effect.key or EncounterScript.MatchKey(effect.name)] = ctx.montage.round or 1
                    --usually hidden from the party, so the console is the
                    --only account of when a locked entry came out.
                    printf("EotW montage: unlocked '%s'%s", tostring(effect.name),
                        cond(effect.hidden, " (hidden clause)", ""))
                else
                    printf("EotW montage: '%s' has no montage to unlock in", tostring(effect.text))
                end
                applied[#applied + 1] = EncounterScript.DescribeUnlock(effect.name)
            elseif effect.kind == "testmod" then
                --"Edge on Capture Them": a standing edge or bane on
                --another test of this montage, for whoever takes it. Held
                --per option NAME in the per-beat state, so several
                --outcomes can pile onto the same test and the roll nets
                --them the way any other edge and bane net.
                if ctx.montage ~= nil then
                    local key = effect.key or EncounterScript.MatchKey(effect.name)
                    ctx.montage.testmods = ctx.montage.testmods or {}
                    ctx.montage.testmods[key] = ctx.montage.testmods[key] or {}
                    local list = ctx.montage.testmods[key]
                    list[#list + 1] = {
                        effect = effect.effect,
                        entryName = ctx.entryName,
                        at = dmhub.serverTime,
                    }
                    printf("EotW montage: %s on '%s'%s", tostring(effect.effect), tostring(effect.name),
                        cond(effect.hidden, " (hidden clause)", ""))
                else
                    printf("EotW montage: '%s' has no montage to apply to", tostring(effect.text))
                end
                applied[#applied + 1] = EncounterScript.DescribeTestMod(effect.effect, effect.name)
            elseif effect.kind == "narrative" then
                --A line is cut into clauses so the grammar can find the
                --mechanical half hiding behind flavour ("You make off with
                --the potions! Each party member gains a Healing Potion") --
                --but the party should read the flavour as the sentence the
                --author wrote, not as one stub per clause with its
                --punctuation stripped. So consecutive prose clauses go back
                --into the SAME entry, rejoined on the punctuation that
                --separated them; only a mechanical clause (which appends an
                --entry of its own) breaks the run.
                --
                --A hidden clause is deliberately left out of the run: it has
                --to stay its own entry for the removal below to take it back
                --off. Because that removal restores #applied, the prose on
                --either side of it still joins -- which is what
                --EncounterScript.VisibleText shows.
                if effect.hidden then
                    applied[#applied + 1] = effect.text
                else
                    if runIndex ~= nil and runIndex == #applied then
                        runText = string.format("%s%s %s", runText, runSep, effect.text)
                    else
                        runText = effect.text
                        applied[#applied + 1] = runText
                        runIndex = #applied
                    end
                    runSep = effect.sep or ""
                    --a full stop, "!" or "?" is part of the prose; a comma
                    --or semicolon only ever joined two clauses, so it is not
                    --left dangling on the end of the entry.
                    local tail = ""
                    if runSep == "." or runSep == "!" or runSep == "?" then
                        tail = runSep
                    end
                    applied[runIndex] = runText .. tail
                end
            end
            if effect.hidden then
                for i = #applied, appliedFrom, -1 do
                    applied[i] = nil
                end
            end
        end
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW montage: effect application failed: %s", tostring(err))
        applied[#applied + 1] = "Some effects could not be applied (see log)"
    end
    return applied, newAllies
end

--Host, once the encounter's combat is under way: pay out every surge the
--montage banked ("at the start of the next combat you gain N surges"), then
--clear the bank so a later tick cannot pay them twice.
--
--This CANNOT run before there is a live initiative queue: Surges are a
--`clearOutsideOfCombat` resource, and creature:AddUnboundedResource silently
--drops the grant when the queue is missing or hidden. So it is driven from
--the EotW host tick's queue-live branch (MapScriptHostThink) rather than
--from combat start, and re-checks the queue itself -- an early call leaves
--the bank untouched for the next tick.
--Record a monster that joined a hero, so the stage (and the right rail) can
--draw its card under theirs. The doc must be inside an open change.
function EncounterMontage.RecordAlly(doc, heroid, charid)
    if doc == nil or heroid == nil or charid == nil then
        return
    end
    doc.data.allies = doc.data.allies or {}
    doc.data.allies[heroid] = doc.data.allies[heroid] or {}
    table.insert(doc.data.allies[heroid], charid)
end

function EncounterMontage.ApplyPendingCombatBoons()
    local doc = EncounterMontage.GetDoc()
    local pending = doc.data.surges
    if type(pending) ~= "table" or next(pending) == nil then
        return
    end
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return
    end

    ElevateToHostPermissions()
    local ok, err = pcall(function()
        for charid, amount in pairs(pending) do
            local token = dmhub.GetCharacterById(charid)
            if token ~= nil and token.valid and (tonumber(amount) or 0) > 0 then
                if GrantSurges(token, tonumber(amount), "Montage boon") then
                    printf("EotW montage: %s begins combat with %s extra", tostring(token.name), EncounterScript.Plural(amount, "surge"))
                end
            end
        end
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW montage: surge payout failed: %s", tostring(err))
    end

    doc:BeginChange()
    doc.data.surges = nil
    doc:CompleteChange("Montage: surges paid out", { undoable = false })
end

--The initiative outcome a montage decided for the next encounter, or nil
--for the normal Draw Steel roll. Read by the encounter beat when it starts
--combat (EncounterOfTheWeek.lua, StartEncounterCombat).
function EncounterMontage.GetInitiativeOutcome()
    local info = EncounterMontage.GetDoc().data.initiative
    if type(info) == "table" and type(info.outcome) == "string" then
        return info.outcome, info.entryName
    end
    return nil
end

--Did the montage win the party immunity to the Surprised condition ("You
--cannot be surprised")? Returns true plus the entry that granted it. The
--heroes still lose the initiative to a "surprised" outcome; only the
--condition is withheld, and from every hero and ally, not just the one who
--earned it.
function EncounterMontage.HasSurpriseImmunity()
    local info = EncounterMontage.GetDoc().data.noSurprise
    if type(info) == "table" then
        return true, info.entryName
    end
    return false
end

--Which sides a montage clause marked Surprised for the coming encounter.
--Returns two values: the party entry (or nil) and the enemy entry (or nil),
--each { entryName, at }.
--
--Kept SEPARATE from data.initiative deliberately. The initiative outcome is
--last-one-wins -- a later "you lose initiative" overrides an earlier
--"surprised" -- and reading the surprise off that outcome meant a second
--initiative consequence in the same montage silently threw the surprise
--away (both mean "the monsters go first", so nothing looked wrong until the
--fight started with no condition on anyone). These flags are sticky: once a
--clause surprises a side, only surprise immunity takes it back.
function EncounterMontage.GetSurprisedSides()
    local info = EncounterMontage.GetDoc().data.surprised
    if type(info) ~= "table" then
        return nil, nil
    end
    local party = info.party
    if type(party) ~= "table" then
        party = nil
    end
    local enemy = info.enemy
    if type(enemy) ~= "table" then
        enemy = nil
    end
    return party, enemy
end

--- the stage (presentation) --------------------------------------------------

function EncounterMontage.IsPresented()
    local presented = false
    pcall(function() presented = GameHud.GetPresentDialogDoc(DIALOG_ID) ~= nil end)
    return presented
end

--Put the script stage up, IF IT IS NOT UP ALREADY.
--
--That guard is the whole difference between a cut and a flicker. Presenting a
--dialog that is already presented does not refresh it: GameHud's presentDialog
--handler nils its reference to the mounted panel for any non-keeplocal dialog
--WITHOUT destroying it (GameHud.lua), and the refresh that follows the
--document write then builds a second one on top. On the presenting client --
--the host, which is the whole table when someone plays solo -- every beat
--change therefore stacked a fresh stage over an orphaned one, and the new
--stage's backdrop had to load and aspect-fit from scratch while the old one
--sat underneath. That is the background flicker. (The orphans also kept
--ticking and kept their claim on the hidden action bar, so the bar would have
--stayed hidden into combat.)
--
--Nothing is lost by not re-sending: the presented-dialog document already says
--the stage is up, and every client reads the live beat from the script
--document the stage monitors.
--
--The presented args are CONSTANT for the same family of reasons: GameHud
--rebuilds a presented dialog from scratch whenever its args change, so a beat
--index in the args made every beat change a teardown.
function EncounterMontage.Present(beatIndex)
    if EncounterMontage.IsPresented() then
        return
    end
    pcall(function()
        GameHud.PresentDialogToUsers(nil, DIALOG_ID, {}, nil)
    end)
end

function EncounterMontage.Hide()
    if EncounterMontage.IsPresented() then
        pcall(function() GameHud.HidePresentedDialog() end)
    end
    EncounterMontage.ClearDismiss()
end

--- dissolving the stage away --------------------------------------------------
--
--The stage does not blink out when the script hands the map back: every client
--plays the engine's screen transition over it (the same dissolve the
--titlescreen uses), so the scene thins away and what is underneath comes
--through it. The clock is shared -- the host stamps `stageDismissAt` on the
--script document and every client runs its own dissolve from that moment --
--so the cut lands together on every screen.

--how long that dissolve takes, and how long the host will wait for the stage
--to actually come down before it stops caring. The encounter beat holds the
--Draw Steel roll until the stage is gone, so a surface that will not go must
--never be able to wedge the fight.
local STAGE_DISMISS_SECONDS = 0.8
local STAGE_DISMISS_TIMEOUT = 4
EncounterMontage.STAGE_DISMISS_SECONDS = STAGE_DISMISS_SECONDS

--The moment the host asked the stage to dissolve, or nil.
function EncounterMontage.DismissAt()
    local at = nil
    pcall(function() at = tonumber(EncounterMontage.GetDoc().data.stageDismissAt) end)
    return at
end

function EncounterMontage.ClearDismiss()
    local doc = EncounterMontage.GetDoc()
    if doc.data.stageDismissAt == nil then
        return
    end
    doc:BeginChange()
    doc.data.stageDismissAt = nil
    doc:CompleteChange("Script stage: dismiss cleared", { undoable = false })
end

--Host, called every tick for as long as the stage still has to go. Stamps the
--shared dissolve clock on the first call and takes the stage down for real
--once that dissolve has played out. Returns true once the stage is gone --
--callers that are waiting to reveal something (the encounter beat waiting to
--roll initiative) should hold until it does.
function EncounterMontage.DismissStage()
    local doc = EncounterMontage.GetDoc()
    local at = tonumber(doc.data.stageDismissAt)
    if not EncounterMontage.IsPresented() then
        if at ~= nil then
            EncounterMontage.ClearDismiss()
        end
        return true
    end
    if at == nil then
        doc:BeginChange()
        doc.data.stageDismissAt = dmhub.serverTime
        doc:CompleteChange("Script stage: dissolving", { undoable = false })
        return false
    end

    --the dissolve is still playing on everyone's screen.
    local age = dmhub.serverTime - at
    if age < STAGE_DISMISS_SECONDS then
        return false
    end

    --it has played: take the surface down. The stamp stays until the stage is
    --really gone (Hide would clear it, and a cleared stamp would just be
    --re-stamped next tick -- an endless dissolve if the hide never took).
    pcall(function() GameHud.HidePresentedDialog() end)
    if age >= STAGE_DISMISS_SECONDS + STAGE_DISMISS_TIMEOUT then
        printf("EotW: the script stage would not come down after %.1fs; carrying on without it", age)
        EncounterMontage.ClearDismiss()
        return true
    end
    return not EncounterMontage.IsPresented()
end

--- host tick ----------------------------------------------------------------

--The tier table to hand the roll dialog: each tier's teaser where it has
--one, its full text otherwise (EncounterScript.TierDisplayText).
function EncounterMontage.TeaserTiers(roll)
    local tiers = {}
    for t in ipairs(roll.tiers) do
        tiers[t] = EncounterScript.TierDisplayText(roll, t, false)
    end
    return tiers
end

local function TierIndexForRoll(roll, tier, natural)
    tier = tonumber(tier) or 1
    if tier < 1 then tier = 1 end
    if tier > 3 then tier = 3 end
    if roll.tiers[4] ~= nil and (tonumber(natural) or 0) >= 19 then
        tier = 4
    end
    return tier
end

--The round is over: every "(Temporary)" entry that appeared in it leaves
--the board for good, and an unvanquished temporary THREAT pays out its
--consequence here rather than at the end of the montage. Each payout goes
--in the montage log marked `expired`, which is what the stage shows the
--party at the top of the next round -- the consequences phase, the only
--other place a consequence is read out, never runs mid-montage.
local function ExpireTemporaryEntries(m, doc, beat, userid)
    local round = m.round or 1
    for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
        if entry.temporary and not EncounterMontage.EntryExpired(m, entry)
            and not EncounterMontage.EntryRemoved(m, entry)
            and EncounterMontage.EntryUnlocked(m, entry)
            and EncounterMontage.EntryAppearRound(m, entry) <= round then
            m.expired = m.expired or {}
            m.expired[entry.id] = true
            local unresolved = entry.kind == "threat" and not (m.vanquished or {})[entry.id]
            if unresolved and entry.consequence ~= nil then
                local applied = EncounterMontage.ApplyEffects(entry.consequence.effects, {
                    heroEntry = nil,
                    userid = userid,
                    entryName = entry.name,
                    entryId = entry.id,
                    montage = m,
                    doc = doc,
                })
                m.log = m.log or {}
                m.log[#m.log + 1] = {
                    round = round,
                    consequence = true,
                    expired = true,
                    entryId = entry.id,
                    entryName = entry.name,
                    applied = applied,
                }
                printf("EotW montage: round %d ended with %s '%s' unresolved; its consequence lands now",
                    round, entry.kind, entry.name)
            else
                printf("EotW montage: round %d carries off %s '%s'%s", round, entry.kind, entry.name,
                    cond(unresolved, " (no consequence written)", ""))
            end
        end
    end
end

--Every hero has acted, or nobody can act (nothing left to approach).
local function RoundComplete(m, beat, heroes)
    if #heroes == 0 then
        return false
    end
    local anyAvailable = false
    for _, entry in ipairs(EncounterScript.EntriesForRound(beat, m.round or 1)) do
        if EncounterMontage.EntryAvailable(m, entry) then
            anyAvailable = true
            break
        end
    end
    if not anyAvailable then
        return true
    end
    for _, hero in ipairs(heroes) do
        if not (m.acted or {})[hero.charid] then
            return false
        end
    end
    return true
end

local function HeroByCharid(heroes, charid)
    for _, hero in ipairs(heroes) do
        if hero.charid == charid then
            return hero
        end
    end
    return nil
end

--- scenes (host side) ---------------------------------------------------------
--
--A turn plays up to three scene parts on the stage: the INTRO when the hero
--approaches, the OPTION's lines once one is picked, and the OUTCOME's lines
--once the roll has landed (EncounterScript's scene grammar). The host
--flattens each part for this hero and this roll into the lines that will
--actually play and stores them on the turn, so every client shows exactly
--the same thing without evaluating the script itself.

--What scene conditions ask about the hero, answered with the same facts and
--matcher the test riders use.
local function SceneEnv(t, option, tier, actors)
    local facts = EncounterMontage.HeroFacts(t.heroid)
    local function Met(text)
        local ok, met = pcall(function()
            return EncounterScript.RequirementMet(EncounterScript.ParseRequirement(text), facts)
        end)
        return ok and met == true
    end
    return {
        tier = tier,
        actors = actors or {},
        speaks = function(language)
            return Met("you speak " .. language)
        end,
        test = function(atom)
            if atom.op == "speaks" then
                return Met("you speak " .. atom.name)
            elseif atom.op == "is" then
                return Met("you are a " .. atom.name)
            elseif atom.op == "has" then
                return Met("you are skilled in " .. atom.name)
            elseif atom.op == "chose" then
                return option ~= nil and EncounterScript.MatchKey(option.name) == EncounterScript.MatchKey(atom.name)
            end
            return false
        end,
    }
end

local function CopyCast(cast)
    local copy = {}
    for i, c in ipairs(cast or {}) do
        copy[i] = { name = c.name, monster = c.monster }
    end
    return copy
end

--Build one scene part onto the turn (t.scene) and return how many lines it
--plays. An entry with no scene of its own still gets an intro: the hero
--approaching, then the entry's "Options:" text if it has one. A line in a
--language the hero does not speak is garbled here, for everyone.
local function BuildScenePart(m, t, entry, option, part, tier)
    local heroName = t.heroName or "The hero"
    local cast = CopyCast(t.scene ~= nil and t.scene.cast or nil)
    local env = SceneEnv(t, option, tier, entry.actors)
    local steps = {}
    if part == "intro" then
        if entry.scripted then
            steps = EncounterScript.FlattenScene(entry.scene, env, cast)
        else
            steps[1] = { kind = "narrate", text = string.format("%s approaches %s...", heroName, entry.name), cast = {} }
        end
        if (entry.approach or "") ~= "" then
            steps[#steps + 1] = { kind = "narrate", text = entry.approach, cast = CopyCast(cast) }
        end
    elseif part == "option" then
        steps = EncounterScript.FlattenScene(option.preScene, env, cast)
    else
        steps = EncounterScript.FlattenScene(option.postScene, env, cast)
    end
    for _, step in ipairs(steps) do
        step.text = EncounterScript.SubstitutePC(step.text, heroName)
        step.line = nil
        for _, e in ipairs(step.emotes or {}) do
            if e.name == "PC" then
                e.name = heroName
                e.side = "left"
            else
                e.side = "right"
            end
        end
        if step.kind == "say" then
            if step.speaker == "PC" then
                step.speaker = heroName
                step.side = "left"
            else
                step.side = "right"
            end
            if step.lang ~= nil and not env.speaks(step.lang) then
                step.text = EncounterScript.Garble(step.text, step.lang)
                step.garbled = true
            end
        end
    end
    m.seq = (m.seq or 0) + 1
    t.scene = { id = m.seq, part = part, steps = steps, cast = cast }
    return #steps
end

--Apply the landed tier of a turn's chosen option and close the turn out:
--effects, allies, the acted/taken bookkeeping, and the log line. Shared by
--the plain "rolled" path and the assisted one, which arrives here with the
--tier the assist shifted it to. An option with outcome lines plays them
--first (ResolveTurn); this runs once they have been read.
local DelveObstacleResolved

local function ApplyResolution(m, doc, t, entry, option, tierIndex, heroes, userid)
    --inside a delve an obstacle's result is applied and the delve goes on;
    --the turn only ends when the hero leaves.
    if t.delve ~= nil and t.delve.obstacleId ~= nil then
        DelveObstacleResolved(m, doc, t, entry, option, tierIndex, heroes, userid)
        return
    end
    local hero = HeroByCharid(heroes, t.heroid)
    local applied, newAllies = EncounterMontage.ApplyEffects(option.roll.effects[tierIndex] or {}, {
        heroEntry = hero,
        userid = userid,
        entryName = entry.name,
        entryId = entry.id,
        montage = m,
        doc = doc,
    })
    if #newAllies > 0 then
        doc.data.allies = doc.data.allies or {}
        doc.data.allies[t.heroid] = doc.data.allies[t.heroid] or {}
        for _, charid in ipairs(newAllies) do
            table.insert(doc.data.allies[t.heroid], charid)
        end
    end
    t.status = "resolved"
    t.tier = tierIndex
    t.tierText = EncounterScript.VisibleText(option.roll.tiers[tierIndex])
    t.applied = applied
    t.resolvedAt = dmhub.serverTime
    m.acted = m.acted or {}
    m.acted[t.heroid] = true
    if entry.kind == "opportunity" then
        m.taken = m.taken or {}
        m.taken[entry.id] = true
    end
    local a = t.assist
    m.log = m.log or {}
    m.log[#m.log + 1] = {
        round = m.round,
        heroid = t.heroid,
        heroName = t.heroName,
        entryId = entry.id,
        entryName = entry.name,
        optionName = option.name,
        tier = tierIndex,
        total = t.total,
        applied = applied,
        assistName = a ~= nil and a.heroName or nil,
        assistOutcome = a ~= nil and a.outcome or nil,
    }
end

--A test has landed on its final tier (after any assist): play the option's
--outcome lines, if it has any for this tier, before anything is applied --
--the witch hands over the potions, THEN they arrive in the haul.
local function ResolveTurn(m, doc, t, entry, option, tierIndex, heroes, userid)
    if option.postScene ~= nil and BuildScenePart(m, t, entry, option, "outcome", tierIndex) > 0 then
        t.tier = tierIndex
        t.pendingTier = tierIndex
        t.resolveUserid = userid
        t.status = "scene"
        t.sceneAfter = "resolve"
        return
    end
    ApplyResolution(m, doc, t, entry, option, tierIndex, heroes, userid)
end

--- delves (host side) ---------------------------------------------------------------
--
--A "Delve: <Name>" option takes the hero into a "# Delve:" section of the
--script, and the whole delve is their turn (user direction 2026-09-24): they
--meet a random obstacle they have not met yet and take one of its tests; its
--result applies at once. Every 1-2 obstacles (the delve's "Chest: every
--N-M") they find a chest and roll its dice table; then they choose to press
--deeper or turn back. A hero with no Recoveries left is forced out, and a
--delve with no obstacles left ends by itself. Leaving plays the delve's
--"Leave" (or "Forced Out") scene and resolves the turn: the entry is taken
--and everything gained goes in the log line. Flat: going deeper is not
--harder, it is just more chests (user direction).

local function HeroRecoveries(heroid)
    local n = 0
    local tok = dmhub.GetCharacterById(heroid)
    if tok ~= nil and tok.valid and tok.properties ~= nil then
        pcall(function() n = tok.properties:RecoveriesAvailableToSpend() or 0 end)
    end
    return n
end

EncounterMontage.HeroRecoveries = HeroRecoveries

local function ChestInterval(delve)
    local lo, hi = 1, 2
    if delve ~= nil and delve.chestEvery ~= nil then
        lo, hi = delve.chestEvery[1], delve.chestEvery[2]
    end
    return math.random(lo, hi)
end

local function DelveAddApplied(t, lines)
    t.delve.applied = t.delve.applied or {}
    for _, line in ipairs(lines or {}) do
        t.delve.applied[#t.delve.applied + 1] = line
    end
end

--a fresh test: nothing of the last obstacle's roll carries over.
local function ClearTest(t)
    t.optionIndex = nil
    t.optionName = nil
    t.rollSeq = nil
    t.tier = nil
    t.pendingTier = nil
    t.resolveUserid = nil
    t.total = nil
    t.natural = nil
    t.baseTier = nil
    t.baseTotal = nil
    t.attrid = nil
    t.skillid = nil
    t.assist = nil
    t.assistOpenedAt = nil
end

local DelveAdvance

--Play one of the delve's own scenes ("chest", "continue", "leave",
--"forced"), with `lead` lines of narration first, then go on to `after`.
local function DelveScene(m, doc, t, heroes, sectionKey, after, lead)
    local delve = EncounterMontage.TurnDelve(t)
    local section = delve ~= nil and delve.sections[sectionKey] or nil
    --each scene of the delve starts with nobody else on stage.
    t.scene = { cast = {} }
    if section ~= nil then
        BuildScenePart(m, t, section, nil, "intro")
    else
        m.seq = (m.seq or 0) + 1
        t.scene = { id = m.seq, part = "intro", steps = {}, cast = {} }
    end
    for i = #(lead or {}), 1, -1 do
        table.insert(t.scene.steps, 1, { kind = "narrate", text = lead[i], cast = {} })
    end
    if #t.scene.steps == 0 then
        DelveAdvance(m, doc, t, heroes, after)
        return
    end
    t.status = "scene"
    t.sceneAfter = after
end

--Walk out: voluntarily ("leave"), with no Recoveries left ("forced"), or
--because every obstacle has been met ("exhausted").
local function DelveLeave(m, doc, t, heroes, why)
    t.delve.obstacleId = nil
    ClearTest(t)
    local lead = nil
    local delve = EncounterMontage.TurnDelve(t)
    local sectionKey = cond(why == "forced", "forced", "leave")
    if why == "forced" and (delve == nil or delve.sections.forced == nil) then
        lead = { string.format("%s has no Recoveries left, and must turn back.", t.heroName or "The hero") }
    elseif why == "exhausted" then
        lead = { "There is nothing further to find here." }
    end
    DelveScene(m, doc, t, heroes, sectionKey, "delve-end", lead)
end

local function DelveNextObstacle(m, doc, t, heroes)
    local delve = EncounterMontage.TurnDelve(t)
    if delve == nil then
        DelveLeave(m, doc, t, heroes, "exhausted")
        return
    end
    if HeroRecoveries(t.heroid) <= 0 then
        DelveLeave(m, doc, t, heroes, "forced")
        return
    end
    local pool = {}
    for _, ob in ipairs(delve.obstacles) do
        if not (t.delve.used or {})[ob.id] then
            pool[#pool + 1] = ob
        end
    end
    if #pool == 0 then
        DelveLeave(m, doc, t, heroes, "exhausted")
        return
    end
    local ob = pool[math.random(1, #pool)]
    t.delve.used = t.delve.used or {}
    t.delve.used[ob.id] = true
    t.delve.obstacleId = ob.id
    ClearTest(t)
    t.scene = { cast = {} }
    if BuildScenePart(m, t, ob, nil, "intro") > 0 then
        t.status = "scene"
        t.sceneAfter = "choosing"
    else
        t.status = "choosing"
    end
end

--The delve is over: the turn resolves like any other, with everything the
--delve granted as its result.
local function DelveFinish(m, doc, t)
    local d = t.delve
    t.status = "resolved"
    t.applied = d.applied or {}
    t.resolvedAt = dmhub.serverTime
    m.acted = m.acted or {}
    m.acted[t.heroid] = true
    m.taken = m.taken or {}
    m.taken[t.entryId] = true
    m.log = m.log or {}
    m.log[#m.log + 1] = {
        round = m.round,
        heroid = t.heroid,
        heroName = t.heroName,
        entryId = t.entryId,
        entryName = d.entryName,
        delve = true,
        depth = d.depth or 0,
        chests = d.chests or 0,
        applied = d.applied or {},
    }
end

--Where a delve scene hands over once it has been read (and straight away
--for a scene with no lines).
DelveAdvance = function(m, doc, t, heroes, after)
    if after == "delve-start" or after == "delve-obstacle" then
        DelveNextObstacle(m, doc, t, heroes)
    elseif after == "delve-chest" then
        m.seq = (m.seq or 0) + 1
        t.rollSeq = m.seq
        t.status = "chest"
    elseif after == "delve-choice" then
        t.status = "delvechoice"
    elseif after == "delve-end" then
        DelveFinish(m, doc, t)
    end
end

--An obstacle's test has landed (after its outcome lines): apply it, then a
--chest, the next obstacle, or the way out.
DelveObstacleResolved = function(m, doc, t, entry, option, tierIndex, heroes, userid)
    local hero = HeroByCharid(heroes, t.heroid)
    local applied, newAllies = EncounterMontage.ApplyEffects(option.roll.effects[tierIndex] or {}, {
        heroEntry = hero,
        userid = userid,
        entryName = t.delve.entryName,
        entryId = t.entryId,
        montage = m,
        doc = doc,
    })
    if #newAllies > 0 then
        doc.data.allies = doc.data.allies or {}
        doc.data.allies[t.heroid] = doc.data.allies[t.heroid] or {}
        for _, charid in ipairs(newAllies) do
            table.insert(doc.data.allies[t.heroid], charid)
        end
    end
    DelveAddApplied(t, applied)
    t.delve.depth = (t.delve.depth or 0) + 1
    t.delve.sinceChest = (t.delve.sinceChest or 0) + 1
    t.delve.obstacleId = nil
    ClearTest(t)
    if HeroRecoveries(t.heroid) <= 0 then
        DelveLeave(m, doc, t, heroes, "forced")
        return
    end
    local delve = EncounterMontage.TurnDelve(t)
    if delve ~= nil and delve.sections.chest ~= nil and delve.sections.chest.table ~= nil
        and t.delve.sinceChest >= (t.delve.chestAt or 1) then
        t.delve.sinceChest = 0
        t.delve.chestAt = ChestInterval(delve)
        DelveScene(m, doc, t, heroes, "chest", "delve-chest")
        return
    end
    DelveNextObstacle(m, doc, t, heroes)
end

--Every line of the playing scene part has been read: move the turn on.
local function FinishScenePart(m, doc, t, beat, heroes)
    local after = t.sceneAfter
    t.sceneAfter = nil
    if after ~= nil and string.sub(after, 1, 6) == "delve-" then
        DelveAdvance(m, doc, t, heroes, after)
        return
    end
    local entry = EncounterMontage.TurnEntry(beat, t)
    if after == "rolling" then
        m.seq = (m.seq or 0) + 1
        t.rollSeq = m.seq
        t.status = "rolling"
    elseif after == "resolve" then
        local option = entry ~= nil and entry.options[t.optionIndex or 0] or nil
        if option == nil or option.roll == nil then
            t.status = "choosing"
            return
        end
        ApplyResolution(m, doc, t, entry, option, t.pendingTier or t.tier or 1, heroes, t.resolveUserid or t.userid)
    else
        t.status = "choosing"
    end
end

--Handle one player request against the (mutable) state. Returns a string
--describing what happened, for the log.
local function HandleRequest(m, doc, userid, req, beat, heroes)
    local kind = req.kind
    if kind == "approach" then
        if m.phase ~= "rounds" or not EncounterMontage.TurnOver(m) then
            return "ignored approach: not the moment"
        end
        local hero = HeroByCharid(heroes, req.heroid)
        if hero == nil or not UserControlsHero(userid, hero) then
            return "ignored approach: not your hero"
        end
        if (m.acted or {})[hero.charid] then
            return "ignored approach: hero already acted"
        end
        local entry = EncounterScript.FindEntry(beat, req.entryId)
        if entry == nil or not EncounterMontage.EntryAvailable(m, entry) then
            return "ignored approach: entry unavailable"
        end
        m.seq = (m.seq or 0) + 1
        m.turn = {
            seq = m.seq,
            userid = userid,
            heroid = hero.charid,
            heroName = hero.name,
            entryId = entry.id,
            status = "choosing",
            startedAt = dmhub.serverTime,
        }
        if BuildScenePart(m, m.turn, entry, nil, "intro") > 0 then
            m.turn.status = "scene"
            m.turn.sceneAfter = "choosing"
        end
        return string.format("%s approaches %s", hero.name, entry.name)
    elseif kind == "pass" then
        --there is no free withdrawal from an approach: the hero may only
        --stand there and do nothing, which spends their turn this round.
        local t = m.turn
        if t == nil or t.userid ~= userid or t.status ~= "choosing" then
            return "ignored pass: not choosing"
        end
        if t.delve ~= nil then
            return "ignored pass: inside a delve (turn back at the next chest)"
        end
        local entry = EncounterMontage.TurnEntry(beat, t)
        m.acted = m.acted or {}
        m.acted[t.heroid] = true
        m.log = m.log or {}
        m.log[#m.log + 1] = {
            round = m.round,
            passed = true,
            heroid = t.heroid,
            heroName = t.heroName,
            entryId = t.entryId,
            entryName = entry ~= nil and entry.name or "",
            applied = {},
        }
        m.turn = nil
        return string.format("%s does nothing", t.heroName or "A hero")
    elseif kind == "choose" then
        local t = m.turn
        if t == nil or t.userid ~= userid or t.status ~= "choosing" then
            return "ignored choose: not choosing"
        end
        local entry = EncounterMontage.TurnEntry(beat, t)
        local option = entry ~= nil and entry.options[tonumber(req.optionIndex) or 0] or nil
        if option == nil or (option.roll == nil and (option.delve == nil or t.delve ~= nil)) then
            return "ignored choose: no such option"
        end
        if option.delve ~= nil and t.delve == nil then
            local script = EncounterMontage.FindMapScript()
            local delve = EncounterScript.FindDelve(script ~= nil and script.parse or nil, option.delve)
            if delve == nil then
                return string.format("ignored choose: no delve '%s' in the script", tostring(option.delve))
            end
            t.optionIndex = tonumber(req.optionIndex)
            t.optionName = option.name
            t.delve = {
                name = delve.name,
                entryName = entry.name,
                depth = 0,
                sinceChest = 0,
                chestAt = ChestInterval(delve),
                used = {},
                chests = 0,
                applied = {},
            }
            --the option's own lines ("PC: In we go") play first.
            if option.preScene ~= nil and BuildScenePart(m, t, entry, option, "option") > 0 then
                t.status = "scene"
                t.sceneAfter = "delve-start"
            else
                DelveNextObstacle(m, doc, t, heroes)
            end
            return string.format("%s enters %s", t.heroName, delve.name)
        end
        --an Allow rider the hero does not meet locks the option; the stage
        --never sends this, but the host is the authority.
        local verdict = EncounterMontage.RiderVerdict(t.heroid, option)
        if verdict ~= nil and not verdict.allowed then
            return string.format("ignored choose: %s does not meet '%s'", t.heroName, EncounterMontage.DescribeUnmet(verdict))
        end
        t.optionIndex = tonumber(req.optionIndex)
        t.optionName = option.name
        --the option's own lines play before the dice come out.
        if option.preScene ~= nil and BuildScenePart(m, t, entry, option, "option") > 0 then
            t.status = "scene"
            t.sceneAfter = "rolling"
            return string.format("%s chooses %s", t.heroName, option.name)
        end
        m.seq = (m.seq or 0) + 1
        t.status = "rolling"
        t.rollSeq = m.seq
        return string.format("%s chooses %s", t.heroName, option.name)
    elseif kind == "cancel" then
        local t = m.turn
        if t ~= nil and t.userid == userid and t.status == "rolling" and t.rollSeq == req.rollSeq then
            t.status = "choosing"
            t.rollSeq = nil
            t.optionIndex = nil
            t.optionName = nil
            return "roll cancelled"
        end
        return "ignored cancel"
    elseif kind == "rolled" then
        local t = m.turn
        if t == nil or t.userid ~= userid or t.status ~= "rolling" or t.rollSeq ~= req.rollSeq then
            return "ignored roll: stale"
        end
        local entry = EncounterMontage.TurnEntry(beat, t)
        local option = entry ~= nil and entry.options[t.optionIndex or 0] or nil
        if option == nil or option.roll == nil then
            t.status = "choosing"
            return "ignored roll: option vanished"
        end
        local tierIndex = TierIndexForRoll(option.roll, req.tier, req.natural)
        --what the acting hero rolled WITH: the assist uses the same
        --characteristic, and a hero may only assist with a skill this one is
        --not already using.
        t.attrid = req.attrid
        t.skillid = req.skillid
        t.tier = tierIndex
        t.total = req.total
        t.natural = req.natural
        t.baseTier = tierIndex
        t.baseTotal = req.total

        --below tier 3, a skilled hero may still lend a hand.
        if tierIndex < 3 and #EncounterMontage.EligibleAssistants(m, beat, heroes) > 0 then
            t.status = "assist"
            t.assistOpenedAt = dmhub.serverTime
            return string.format("%s rolled tier %d on %s -- assistance is offered", t.heroName, tierIndex, entry.name)
        end

        ResolveTurn(m, doc, t, entry, option, tierIndex, heroes, userid)
        return string.format("%s rolled tier %d on %s", t.heroName, tierIndex, entry.name)
    elseif kind == "assist" then
        local t = m.turn
        if t == nil or t.status ~= "assist" then
            return "ignored assist: not the moment"
        end
        local hero = HeroByCharid(heroes, req.heroid)
        if hero == nil or not UserControlsHero(userid, hero) then
            return "ignored assist: not your hero"
        end
        local match = nil
        for _, candidate in ipairs(EncounterMontage.EligibleAssistants(m, beat, heroes)) do
            if candidate.charid == hero.charid then
                match = candidate
                break
            end
        end
        if match == nil then
            return "ignored assist: hero cannot assist this test"
        end
        m.seq = (m.seq or 0) + 1
        t.assist = {
            userid = userid,
            heroid = hero.charid,
            heroName = hero.name,
            skillid = match.skillid,
            skillName = match.skillName,
            status = "rolling",
            rollSeq = m.seq,
            startedAt = dmhub.serverTime,
        }
        t.status = "assisting"
        return string.format("%s steps in to assist %s", hero.name, t.heroName or "the test")
    elseif kind == "giveItem" then
        --a hero's player drags an icon from their haul onto another hero's
        --card (EncounterMontageStage.CreateItemIcon): one unit of the item
        --moves between the two inventories, and the haul records follow.
        --Allowed in any phase -- sharing the loot is never "not the moment".
        local hero = HeroByCharid(heroes, req.heroid)
        if hero == nil or not UserControlsHero(userid, hero) then
            return "ignored give: not your hero"
        end
        local target = HeroByCharid(heroes, req.targetId)
        if target == nil or target.charid == hero.charid then
            return "ignored give: no such hero to give to"
        end
        local entry = FindRecordedItem(doc, hero.charid, req.itemid)
        if entry == nil then
            return "ignored give: hero did not gain that item here"
        end
        if InventoryQuantity(hero.token, req.itemid) < 1 then
            --gained here, but already used up or dropped: the icon is stale.
            UnrecordItem(doc, hero.charid, req.itemid, entry.qty or 1)
            return "ignored give: item no longer in the hero's inventory"
        end
        ElevateToHostPermissions()
        local ok, err = pcall(function()
            GrantItem(target.token, req.itemid, entry.name, 1)
            GrantItem(hero.token, req.itemid, entry.name, -1)
        end)
        DropHostPermissions()
        if not ok then
            error(err)
        end
        RecordItem(doc, target.charid, req.itemid, entry.name, 1)
        UnrecordItem(doc, hero.charid, req.itemid, 1)
        return string.format("%s hands %s to %s", hero.name, tostring(entry.name), target.name)
    elseif kind == "assistCancel" then
        local t = m.turn
        local a = t ~= nil and t.assist or nil
        if a ~= nil and a.userid == userid and a.status == "rolling" and a.rollSeq == req.rollSeq then
            t.assist = nil
            t.status = "assist"
            return "assist withdrawn"
        end
        return "ignored assist cancel"
    elseif kind == "assistRolled" then
        local t = m.turn
        local a = t ~= nil and t.assist or nil
        if t == nil or a == nil or a.userid ~= userid or t.status ~= "assisting" or a.rollSeq ~= req.rollSeq then
            return "ignored assist roll: stale"
        end
        local entry = EncounterMontage.TurnEntry(beat, t)
        local option = entry ~= nil and entry.options[t.optionIndex or 0] or nil
        if option == nil or option.roll == nil then
            t.status = "choosing"
            t.assist = nil
            return "ignored assist roll: option vanished"
        end
        local assistTier = tonumber(req.tier) or 1
        if assistTier < 1 then assistTier = 1 end
        if assistTier > 3 then assistTier = 3 end
        a.tier = assistTier
        a.total = req.total
        a.natural = req.natural
        a.outcome = ASSIST_OUTCOMES[assistTier]
        a.status = "resolved"
        --assisting costs the helper their turn this round, whatever it rolled.
        m.acted = m.acted or {}
        m.acted[a.heroid] = true
        local tierIndex, newTotal = EncounterMontage.ApplyAssistToTier(a.outcome, t.baseTier, t.baseTotal)
        tierIndex = TierIndexForRoll(option.roll, tierIndex, t.natural)
        t.total = newTotal
        ResolveTurn(m, doc, t, entry, option, tierIndex, heroes, userid)
        return string.format("%s assists (%s): %s ends on tier %d", a.heroName or "A hero",
            tostring(a.outcome), t.heroName or "the test", tierIndex)
    elseif kind == "noassist" then
        local t = m.turn
        if t == nil or t.status ~= "assist" then
            return "ignored noassist"
        end
        --only the hero taking the test may wave the offer away.
        if t.userid ~= userid then
            return "ignored noassist: not your test"
        end
        local entry = EncounterMontage.TurnEntry(beat, t)
        local option = entry ~= nil and entry.options[t.optionIndex or 0] or nil
        if option == nil or option.roll == nil then
            t.status = "choosing"
            return "ignored noassist: option vanished"
        end
        ResolveTurn(m, doc, t, entry, option, t.baseTier or t.tier or 1, heroes, userid)
        return string.format("%s takes the result unassisted", t.heroName or "The hero")
    elseif kind == "chestRolled" then
        local t = m.turn
        if t == nil or t.delve == nil or t.status ~= "chest" or t.userid ~= userid or t.rollSeq ~= req.rollSeq then
            return "ignored chest roll: stale"
        end
        local delve = EncounterMontage.TurnDelve(t)
        local chest = delve ~= nil and delve.sections.chest or nil
        local total = math.floor(tonumber(req.total) or 1)
        local row = chest ~= nil and EncounterScript.ChestRow(chest.table, total) or nil
        local lead = { string.format("%s rolls %d.", t.heroName or "The hero", total) }
        if row ~= nil then
            local hero = HeroByCharid(heroes, t.heroid)
            local applied = EncounterMontage.ApplyEffects(row.effects, {
                heroEntry = hero,
                userid = userid,
                entryName = t.delve.entryName,
                entryId = t.entryId,
                montage = m,
                doc = doc,
            })
            DelveAddApplied(t, applied)
            lead[1] = string.format("%s rolls %d: %s", t.heroName or "The hero", total, EncounterScript.VisibleText(row.text))
        end
        t.delve.chests = (t.delve.chests or 0) + 1
        t.rollSeq = nil
        DelveScene(m, doc, t, heroes, "continue", "delve-choice", lead)
        return string.format("%s opens a chest: %d", t.heroName or "A hero", total)
    elseif kind == "delveOn" or kind == "delveOut" then
        local t = m.turn
        if t == nil or t.delve == nil or t.status ~= "delvechoice" or t.userid ~= userid then
            return "ignored delve choice: not the moment"
        end
        if kind == "delveOn" then
            DelveNextObstacle(m, doc, t, heroes)
            return string.format("%s presses deeper into %s", t.heroName or "A hero", t.delve.entryName or "the delve")
        end
        DelveLeave(m, doc, t, heroes, "leave")
        return string.format("%s turns back from %s", t.heroName or "A hero", t.delve.entryName or "the delve")
    elseif kind == "continue" then
        if m.phase ~= "consequences" then
            return "ignored continue"
        end
        local idx = m.consequenceIndex or 1
        local entryId = (m.consequences or {})[idx]
        if entryId == nil then
            m.phase = "done"
            return "montage done"
        end
        local entry = EncounterScript.FindEntry(beat, entryId)
        local applied = {}
        if entry ~= nil and entry.consequence ~= nil then
            applied = EncounterMontage.ApplyEffects(entry.consequence.effects, {
                heroEntry = nil,
                userid = userid,
                entryName = entry.name,
                entryId = entry.id,
                montage = m,
                doc = doc,
            })
        end
        m.lastApplied = { entryId = entryId, entryName = entry ~= nil and entry.name or "", applied = applied }
        m.log = m.log or {}
        m.log[#m.log + 1] = { consequence = true, entryId = entryId, entryName = entry ~= nil and entry.name or "", applied = applied }
        m.consequenceIndex = idx + 1
        if m.consequences[idx + 1] == nil then
            m.phase = "done"
            m.doneAt = dmhub.serverTime
        end
        return string.format("consequence of %s applied", entryId)
    elseif kind == "reset" then
        --dev: restart the montage from round 1 (state only; effects already
        --applied are not undone).
        return "reset"
    end
    return "ignored unknown request " .. tostring(kind)
end

--Host: make the party-size draw for this beat and write it to the montage
--state, so every client agrees on what is on the board. Rolled once, at the
--moment the party has arrived (the hero roster is only trustworthy then --
--Begin can run before a single hero token is placed). A beat with no
--directives still gets an empty set: `m.removed == nil` is what the stage
--reads as "the draw has not been made, show nothing yet".
local function RollRemovals(m, beat)
    local heroes = EncounterMontage.Heroes()
    local removed = EncounterScript.ChooseRemovedEntries(beat, #heroes)
    m.removed = removed
    --kept on the document so the draw is still explicable long after the
    --console scrollback is gone.
    m.removedForPartySize = #heroes
    --The draw is invisible to the party, so the console is the ONLY record
    --of what a week actually played with: log the party size, every
    --directive and whether it fired, and each entry that went. All of this
    --is printf (the Director's console / the log), never the montage log
    --the stage shows.
    if EncounterScript.HasScaling(beat) then
        printf("EotW montage: party-size scaling -- %d heroes", #heroes)
        for _, r in ipairs(beat.rounds or {}) do
            for _, d in ipairs(r.scaling or {}) do
                local applies = #heroes >= d.min and (d.max == nil or #heroes <= d.max)
                printf("EotW montage:   round %d: '%s' -- %s", r.number, d.text,
                    cond(applies, "APPLIES", "out of range at this party size"))
            end
        end
        local n = 0
        for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
            if removed[entry.id] then
                n = n + 1
                printf("EotW montage:   round %d REMOVED %s '%s' [%s]",
                    entry.round, entry.kind, entry.name, entry.id)
            elseif (entry.required or entry.locked) and EncounterScript.RoundHasScaling(beat, entry.round) then
                printf("EotW montage:   round %d kept %s '%s' (%s)",
                    entry.round, entry.kind, entry.name,
                    cond(entry.required, cond(entry.locked, "Required, Locked", "Required"), "Locked"))
            end
        end
        printf("EotW montage: party-size scaling removed %d of %d entries",
            n, #EncounterScript.MontageEntries(beat))
    end
    return removed
end

--The "(Locked)" entries of a beat and whether anything has let them out
--yet, for "/eotwmontage state": a hidden unlock leaves no trace a player
--can see, so this is how a montage gets explained after the fact.
function EncounterMontage.DescribeLocks(beat, m)
    local out = {}
    local any = false
    for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
        if entry.locked then
            if not any then
                out[#out + 1] = "locked entries:"
                any = true
            end
            out[#out + 1] = string.format("  %s round %d %s '%s'%s [%s]",
                cond(EncounterMontage.EntryUnlocked(m, entry), "UNLOCKED", "locked  "),
                entry.round, entry.kind, entry.name,
                cond(EncounterMontage.EntryUnlocked(m, entry),
                    string.format(" (appeared in round %d)", EncounterMontage.EntryAppearRound(m, entry)), ""),
                entry.id)
        end
    end
    --an unlock whose name matched nothing is a typo the parse warned
    --about; show it here too, since this is where it will be looked for.
    for key in pairs((m or {}).unlocked or {}) do
        local found = false
        for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
            if entry.locked and EncounterScript.MatchKey(entry.name) == key then
                found = true
                break
            end
        end
        if not found then
            out[#out + 1] = string.format("  UNLOCKED '%s' -- matches no (Locked) entry", key)
        end
    end
    return out
end

--The "(Temporary)" entries of a beat and whether the round they appeared
--in has carried them off yet, for "/eotwmontage state".
function EncounterMontage.DescribeTemporary(beat, m)
    local out = {}
    for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
        if entry.temporary then
            if #out == 0 then
                out[#out + 1] = "temporary entries:"
            end
            local state = "waiting"
            if EncounterMontage.EntryExpired(m, entry) then
                state = "EXPIRED"
            elseif not EncounterMontage.EntryUnlocked(m, entry) then
                state = "locked"
            elseif EncounterMontage.EntryRemoved(m, entry) then
                state = "removed"
            end
            out[#out + 1] = string.format("  %-8s %s '%s', appears round %d [%s]",
                state, entry.kind, entry.name, EncounterMontage.EntryAppearRound(m, entry), entry.id)
        end
    end
    return out
end

--The standing edges and banes in force, for "/eotwmontage state": like a
--hidden unlock, an "Edge on <option>" outcome usually leaves no trace a
--player can see.
function EncounterMontage.DescribeTestMods(beat, m)
    local out = {}
    local mods = (m or {}).testmods or {}
    local seen = {}
    for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
        for _, option in ipairs(entry.options) do
            local key = EncounterScript.MatchKey(option.name)
            local list = mods[key]
            if list ~= nil and not seen[key] then
                seen[key] = true
                if #out == 0 then
                    out[#out + 1] = "standing edges and banes:"
                end
                local parts = {}
                for _, g in ipairs(list) do
                    parts[#parts + 1] = string.format("%s (from %s)",
                        EncounterScript.RiderLabel(g.effect), tostring(g.entryName))
                end
                out[#out + 1] = string.format("  '%s': %s", option.name, table.concat(parts, ", "))
            end
        end
    end
    for key, list in pairs(mods) do
        if not seen[key] then
            out[#out + 1] = string.format("  '%s' -- matches no option (%d grant(s) wasted)", key, #list)
        end
    end
    return out
end

--A readable account of the party-size draw for "/eotwmontage state": what
--the montage document holds is a set of entry ids, which says nothing on
--its own. Returns a list of lines (empty when the beat has no directives).
function EncounterMontage.DescribeRemovals(beat, m)
    local out = {}
    if beat == nil or not EncounterScript.HasScaling(beat) then
        return out
    end
    local removed = (m or {}).removed
    if removed == nil then
        out[#out + 1] = "party-size scaling: not rolled yet (the party has not arrived)"
        return out
    end
    out[#out + 1] = string.format("party-size scaling (rolled for %s heroes):",
        tostring(m.removedForPartySize or "?"))
    for _, r in ipairs(beat.rounds or {}) do
        for _, d in ipairs(r.scaling or {}) do
            out[#out + 1] = string.format("  round %d directive: %s", r.number, d.text)
        end
    end
    local n = 0
    for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
        if removed[entry.id] then
            n = n + 1
            out[#out + 1] = string.format("  REMOVED round %d %s '%s' [%s]",
                entry.round, entry.kind, entry.name, entry.id)
        end
    end
    if n == 0 then
        out[#out + 1] = "  nothing was removed"
    end
    return out
end

--Host: seed the state for a montage beat and present the stage to everyone.
--The beat starts in the "arriving" phase -- the stage is up, but nobody can
--act -- and HostTick moves it to "rounds" on its first tick, which the map
--script only runs once every expected player has arrived. So the host can
--present the opening montage during its own arrival setup, before the party
--is in (and before its heroes are even placed), and the stage is what every
--player's loading screen reveals.
function EncounterMontage.Begin(script, beat, beatIndex)
    local doc = EncounterMontage.GetDoc()
    doc:BeginChange()
    doc.data.montage = {
        beatIndex = beatIndex,
        round = 1,
        phase = "arriving",
        acted = {},
        taken = {},
        vanquished = {},
        requests = {},
        handled = {},
        log = {},
        seq = 0,
    }
    doc.data.stageDismissAt = nil
    --scene ids restart with m.seq, so a cursor left over from an earlier
    --run could otherwise skip the new run's first scene.
    doc.data.montageScene = nil
    doc:CompleteChange("Montage started", { undoable = false })
    pcall(EncounterMontage.PrepareBoonAssets, beat)
    printf("EotW montage: beat %d started (%d rounds)", beatIndex, EncounterScript.RoundCount(beat))
    EncounterMontage.Present(beatIndex)
end

--Run the montage beat from the host tick. Returns "running" while the
--montage plays and "done" once every round and consequence has played.
function EncounterMontage.HostTick(script, beat, beatIndex)
    local doc = EncounterMontage.GetDoc()
    local m = doc.data.montage
    if type(m) ~= "table" or m.beatIndex ~= beatIndex then
        EncounterMontage.Begin(script, beat, beatIndex)
        return "running"
    end

    if m.phase == "arriving" then
        --the host tick only runs once the whole party has arrived: open
        --the rounds.
        doc:BeginChange()
        doc.data.montage.phase = "rounds"
        RollRemovals(doc.data.montage, beat)
        doc:CompleteChange("Montage: the party has arrived", { undoable = false })
        m = doc.data.montage
        printf("EotW montage: beat %d -- the party has arrived; round 1 begins", beatIndex)
    end

    if m.removed == nil and m.phase ~= "arriving" then
        --belt and braces: a montage that somehow reached the rounds without
        --the draw (a state written by an older client) makes it now.
        doc:BeginChange()
        RollRemovals(doc.data.montage, beat)
        doc:CompleteChange("Montage: party-size scaling", { undoable = false })
        m = doc.data.montage
    end

    if m.phase == "done" then
        --linger so everyone sees the last consequence (or the "over" card).
        local age = dmhub.serverTime - (tonumber(m.doneAt) or 0)
        if age >= DONE_LINGER_SECONDS then
            return "done"
        end
        return "running"
    end

    if not EncounterMontage.IsPresented() then
        EncounterMontage.Present(beatIndex)
    end

    local heroes = EncounterMontage.Heroes()

    --requests, in a stable order (by userid), each at most once.
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
    m = doc.data.montage
    for _, p in ipairs(pending) do
        m.handled = m.handled or {}
        m.handled[p.userid] = p.req.seq
        if p.req.kind == "reset" then
            resetRequested = true
        else
            local ok, result = pcall(HandleRequest, m, doc, p.userid, p.req, beat, heroes)
            if not ok then
                printf("EotW montage: request %s from %s failed: %s", tostring(p.req.kind), tostring(p.userid), tostring(result))
            elseif result ~= nil then
                printf("EotW montage: %s", tostring(result))
            end
        end
    end

    --the acting hero's player has read the last line of the scene part on
    --stage (EncounterMontage.AdvanceScene): the turn moves on. There is no
    --timeout -- only that player paces their scene (user direction
    --2026-09-23).
    if m.turn ~= nil and m.turn.status == "scene" then
        local t = m.turn
        local scene = t.scene or {}
        local cursor = doc.data.montageScene
        if type(cursor) == "table" and cursor.id == scene.id
            and (tonumber(cursor.index) or 1) > #(scene.steps or {}) then
            FinishScenePart(m, doc, t, beat, heroes)
        end
    end

    --a claimed assist that never rolls hands the slot back, and the window
    --below then closes on its own clock.
    if m.turn ~= nil and m.turn.status == "assisting" and m.turn.assist ~= nil then
        local age = dmhub.serverTime - (tonumber(m.turn.assist.startedAt) or dmhub.serverTime)
        if age >= ASSIST_ROLL_SECONDS then
            printf("EotW montage: %s never rolled their assist; the slot is free again",
                tostring(m.turn.assist.heroName))
            m.turn.assist = nil
            m.turn.status = "assist"
        end
    end

    --nobody stepped in: the assist window closes itself so an absent party
    --cannot wedge the montage, and the test keeps its own result. An empty
    --window is never shown at all (user direction 2026-09-19) -- with no
    --eligible hero it closes on the spot rather than waiting out the clock,
    --which also covers eligibility falling away after it opened.
    if m.turn ~= nil and m.turn.status == "assist" then
        local age = dmhub.serverTime - (tonumber(m.turn.assistOpenedAt) or dmhub.serverTime)
        if #EncounterMontage.EligibleAssistants(m, beat, heroes) == 0 then
            age = ASSIST_WINDOW_SECONDS
        end
        if age >= ASSIST_WINDOW_SECONDS then
            local t = m.turn
            local entry = EncounterMontage.TurnEntry(beat, t)
            local option = entry ~= nil and entry.options[t.optionIndex or 0] or nil
            if option ~= nil and option.roll ~= nil then
                ResolveTurn(m, doc, t, entry, option, t.baseTier or t.tier or 1, heroes, t.userid)
                printf("EotW montage: no assistance offered for %s; the result stands", tostring(t.heroName))
            else
                t.status = "choosing"
            end
        end
    end

    --round progression. A resolved turn is over as far as the round is
    --concerned (its result is in the log); it leaves with the round.
    if m.phase == "rounds" and EncounterMontage.TurnOver(m) and RoundComplete(m, beat, heroes) then
        m.turn = nil
        local rounds = EncounterScript.RoundCount(beat)
        if (m.round or 1) < rounds then
            ExpireTemporaryEntries(m, doc, beat, nil)
            m.round = (m.round or 1) + 1
            m.acted = {}
            printf("EotW montage: round %d begins", m.round)
        else
            --every unvanquished threat, in document order, delivers its
            --consequence.
            local list = {}
            for _, entry in ipairs(EncounterScript.MontageEntries(beat)) do
                if entry.kind == "threat" and not (m.vanquished or {})[entry.id]
                    and not EncounterMontage.EntryRemoved(m, entry)
                    and not EncounterMontage.EntryExpired(m, entry)
                    and EncounterMontage.EntryUnlocked(m, entry) then
                    list[#list + 1] = entry.id
                end
            end
            m.consequences = list
            m.consequenceIndex = 1
            m.lastApplied = nil
            if #list == 0 then
                m.phase = "done"
                m.doneAt = dmhub.serverTime
                printf("EotW montage: complete, no threats remain")
            else
                m.phase = "consequences"
                printf("EotW montage: %d unresolved threats", #list)
            end
        end
    end

    if resetRequested then
        doc.data.montage = nil
    end
    doc:CompleteChange("Montage tick", { undoable = false })

    if resetRequested then
        return "running"
    end
    if doc.data.montage ~= nil and doc.data.montage.phase == "done" then
        return "done"
    end
    return "running"
end

--- client tick ------------------------------------------------------------------

--the roll the local client has already launched, so a turn is rolled once.
local m_launchedRollSeq = nil

--Show a montage roll dialog. Everything both montage rolls share: the wait
--for a free roll surface, the synthetic test ability in the timeline
--sidebar with the dialog embedded in its card, the share that gives every
--other client the read-only remote copy, and the completion that reports
--the tier to the host.
--
--args: creature, heroToken, title, rollType, roll, modifiers, tiers,
--      rollSeq, expectedStatus (the turn status this roll is still wanted
--      for), CurrentRollSeq (pulls the live rollSeq out of a turn),
--      completeKind, cancelKind, extra (fields merged into the completion
--      request).
local function ShowMontageRoll(args)
    local c = args.creature
    local title = args.title
    local rollSeq = args.rollSeq
    local rollProperties = RollPropertiesPowerTable.new {
        tiers = args.tiers,
        fullyImplemented = true,
    }

    dmhub.Coroutine(function()
        local waited = 0
        while (not mod.unloaded) and CharacterPanel.AnyRollDialogShown() do
            coroutine.yield(0.05)
            waited = waited + 1
            if waited > 600 then break end
        end
        if mod.unloaded or CharacterPanel.AnyRollDialogShown() then
            --could not show; let the turn be re-rolled by clearing the
            --launch mark so the next client tick tries again.
            m_launchedRollSeq = nil
            return
        end
        --the turn may have moved on while we waited.
        local m = EncounterMontage.GetState()
        if m == nil or m.turn == nil or m.turn.status ~= args.expectedStatus or args.CurrentRollSeq(m.turn) ~= rollSeq then
            return
        end

        --The same presentation as a characteristic test clicked on the
        --character panel (creature:ShowCharacteristicRollDialog): a synthetic
        --test ability is shown in the timeline sidebar and the roll dialog is
        --embedded in its card, so the roll sits at the side of the screen
        --like every other roll in the game. The synthetic single target (the
        --roller) is what lets post-roll edges/banes refresh the tier.
        local syntheticAbility = ActivatedAbility.Create{ isTest = true, name = title }
        local rollerToken = dmhub.LookupToken(c) or args.heroToken
        local multitargets = {
            {
                token = rollerToken,
                boons = 0,
                banes = 0,
                modifiers = args.modifiers,
                triggers = {},
            },
        }
        local displaying = false
        pcall(function()
            --we waited for every roll surface to clear, so any display lock
            --left behind is stale.
            CharacterPanel.ForceUnlockDisplayAbility()
            displaying = CharacterPanel.DisplayAbility(rollerToken, syntheticAbility, nil, { lock = true, renderAsAbility = true })
        end)
        --Everyone watches this roll: share the card so the other clients get
        --the read-only remote copy of the dialog, exactly as on a hero's
        --combat turn. The combat path shares from HighlightAbilitySection,
        --gated on the initiative turn; a montage has no queue, so share
        --explicitly. Also what the stage's live tier highlight reads.
        if displaying and CharacterPanel.ShareDisplayedAbility ~= nil then
            pcall(function() CharacterPanel.ShareDisplayedAbility(rollerToken, syntheticAbility) end)
        end

        local function Finish()
            if displaying then
                pcall(function() CharacterPanel.HideAbility(syntheticAbility) end)
            end
        end

        local function ShowRollDialog(dialog)
            if dialog == nil or not dialog.valid then
                --GameHud.instance is FALSE until the hud exists, and indexing
                --it raises. A reload or a restart taken mid-roll relaunches
                --the roll while the loading screen is still up and lands
                --exactly there, which used to kill the coroutine and wedge the
                --turn in "rolling" for the rest of the session. Bail quietly
                --instead: the launch watermark is cleared below, so the client
                --tick simply tries again once the hud is up.
                local hud = rawget(_G, "GameHud")
                hud = hud ~= nil and hud.instance or nil
                dialog = (hud ~= nil and hud ~= false) and hud.rollDialog or nil
            end
            if dialog == nil or not dialog.valid then
                Finish()
                m_launchedRollSeq = nil
                return
            end
            dialog.data.ShowDialog {
                title = title,
                description = title,
                creature = c,
                ability = syntheticAbility,

                type = args.rollType,
                roll = args.roll,
                modifiers = args.modifiers,
                multitargets = multitargets,
                targetCreature = c,
                showDialogDuringRoll = true,
                amendable = true,

                rollProperties = rollProperties,
                PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(rollProperties),

                completeRoll = function(rollInfo)
                    Finish()
                    local tier = 1
                    pcall(function() tier = RollUtils.DiceResultToTier(rollInfo) end)
                    local natural = nil
                    pcall(function() natural = rollInfo.naturalRoll end)
                    local total = nil
                    pcall(function() total = rollInfo.total end)
                    local req = { rollSeq = rollSeq, tier = tier, total = total, natural = natural }
                    for k, v in pairs(args.extra or {}) do
                        req[k] = v
                    end
                    EncounterMontage.SendRequest(args.completeKind, req)
                end,

                cancelRoll = function()
                    Finish()
                    m_launchedRollSeq = nil
                    EncounterMontage.SendRequest(args.cancelKind, { rollSeq = rollSeq })
                end,
            }
        end

        --the embedded (timeline) dialog when the sidebar is available, else
        --the standalone roll dialog.
        local embeddedDialog = nil
        pcall(function() embeddedDialog = CharacterPanel.EmbedDialogInAbility() end)
        if embeddedDialog ~= nil then
            dmhub.Schedule(0.05, function()
                if mod.unloaded then
                    return
                end
                ShowRollDialog(embeddedDialog)
            end)
        else
            ShowRollDialog(nil)
        end
    end)
end

--Turn the "Skilled" modifier of a montage roll into the named chip a
--characteristic test shows: "Skilled in Empathize", forced on, when the
--roller is trained in one of the listed skills. Returns the skill id it
--settled on (nil when the roller is trained in none of them).
--
--"only" narrows the search to one skill -- what an assist does, where the
--helper is by definition assisting with a particular skill.
local function ApplySkilledModifier(c, modifiers, skills, only)
    local usedSkillId = nil
    for _, m in ipairs(modifiers) do
        if m.modifier.name == "Skilled" then
            local skillNames = {}
            local found = false
            for _, skillid in ipairs(skills) do
                if only == nil or skillid == only then
                    local skillInfo = dmhub.GetTable(Skill.tableName)[skillid]
                    if skillInfo ~= nil and c:ProficientInSkill(skillInfo) then
                        found = true
                        usedSkillId = skillid
                        m.modifier = DeepCopy(m.modifier)
                        m.modifier.name = string.format(tr("Skilled in %s"), skillInfo.name)
                        m.modifier.description = string.format(tr("Skill in %s gives you +2 on this roll"), skillInfo.name)
                        m.modifier.activationCondition = true
                        m.hint.result = true
                        break
                    elseif skillInfo ~= nil then
                        skillNames[#skillNames + 1] = skillInfo.name
                    end
                end
            end
            if (not found) and #skillNames > 0 then
                m.modifier = DeepCopy(m.modifier)
                m.modifier.description = string.format(tr("Not skilled in %s"), table.concat(skillNames, " or "))
            end
        end
    end
    return usedSkillId
end

--The best of the characteristics a montage roll lists, for this creature.
--Returns attrid (nil when none matched) and the modifier to roll with.
local function BestCharacteristic(c, characteristics)
    local attrid = nil
    local bestModifier = nil
    for id, _ in pairs(characteristics) do
        local attr = c:GetAttribute(id)
        if attr ~= nil then
            local modifier = attr:Modifier()
            if bestModifier == nil or modifier > bestModifier then
                bestModifier = modifier
                attrid = id
            end
        end
    end
    return attrid, bestModifier or 0
end

--Show the roll dialog for the current turn's option: 2d10 + the best of
--the listed characteristics, the Skilled chip for a listed skill, the tiers
--The rider effects the hero earned ("Edge: you speak Caelian"), plus any
--standing edge or bane the montage granted this test ("Edge on Capture
--Them"), become pre-ticked chips in the roll dialog. RiderVerdict folds
--the grants in as applied riders, so core builds them all the same way
--(TestRiders).
local function AppendRiderModifiers(modifiers, verdict, rollType)
    TestRiders.AppendModifiers(modifiers, verdict, rollType)
end

--Show the roll dialog for the current turn's option: 2d10 + the best of
--the listed characteristics, the Skilled chip for a listed skill, the tiers
--from the script. Mirrors creature:RollCustomPowerTableTest (MCDMCreature.lua)
--with a completion that reports the tier -- and what it rolled with, which
--is what decides who may assist it -- to the host.
local function LaunchRoll(turn, entry, option, heroToken)
    local c = heroToken.properties
    local characteristics, skills = EncounterScript.ParseAttr(option.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
    local title = string.format("%s: %s", option.roll.name, option.roll.attr)

    local attrid, bestModifier = BestCharacteristic(c, characteristics)
    if attrid == nil then
        printf("EotW montage: no characteristic matched '%s'; rolling with no bonus", option.roll.attr)
    end

    local rollType = "test_power_roll"
    local roll = string.format("2d10 + %d", bestModifier)
    local modifiers = {}
    if attrid ~= nil then
        modifiers = c:GetModifiersForPowerRoll(roll, rollType, { attribute = attrid, title = title })
    end
    local usedSkillId = ApplySkilledModifier(c, modifiers, skills)
    AppendRiderModifiers(modifiers, EncounterMontage.RiderVerdict(heroToken.charid, option), rollType)

    ShowMontageRoll {
        creature = c,
        heroToken = heroToken,
        title = title,
        rollType = rollType,
        roll = roll,
        modifiers = modifiers,
        --the dialog's power table shows teasers, never the hidden text
        tiers = EncounterMontage.TeaserTiers(option.roll),
        rollSeq = turn.rollSeq,
        expectedStatus = "rolling",
        CurrentRollSeq = function(t) return t.rollSeq end,
        completeKind = "rolled",
        cancelKind = "cancel",
        extra = { attrid = attrid, skillid = usedSkillId },
    }
end

--Show the assist roll for the hero who stepped in: the SAME characteristic
--the test itself used, with the assisting hero's own modifier and an
--automatic Skilled +2 for the skill they are helping with, against the
--fixed assist tier table (bane / edge / double edge).
local function LaunchAssistRoll(turn, entry, option, assistToken)
    local a = turn.assist
    local c = assistToken.properties
    local attrid = turn.attrid
    local attrName = nil
    if attrid ~= nil and creature.attributesInfo[attrid] ~= nil then
        attrName = creature.attributesInfo[attrid].description
    end
    local title = string.format("Assist %s: %s", turn.heroName or "the test", a.skillName or attrName or option.roll.name)

    local modifier = 0
    if attrid ~= nil then
        local attr = c:GetAttribute(attrid)
        if attr ~= nil then
            modifier = attr:Modifier()
        end
    end

    local rollType = "test_power_roll"
    local roll = string.format("2d10 + %d", modifier)
    local modifiers = {}
    if attrid ~= nil then
        modifiers = c:GetModifiersForPowerRoll(roll, rollType, { attribute = attrid, title = title })
    end
    --the helper assists WITH a skill, so the chip is never in doubt.
    ApplySkilledModifier(c, modifiers, { a.skillid }, a.skillid)

    ShowMontageRoll {
        creature = c,
        heroToken = assistToken,
        title = title,
        rollType = rollType,
        roll = roll,
        modifiers = modifiers,
        tiers = ASSIST_TIERS,
        rollSeq = a.rollSeq,
        expectedStatus = "assisting",
        CurrentRollSeq = function(t) return (t.assist or {}).rollSeq end,
        completeKind = "assistRolled",
        cancelKind = "assistCancel",
    }
end

--Per-client: when it is this user's hero's turn to roll, show the roll
--dialog once per rollSeq. Called from the per-client driver and the stage.
function EncounterMontage.ClientTick()
    local m = EncounterMontage.GetState()
    if m == nil or m.turn == nil then
        m_launchedRollSeq = nil
        return
    end
    local t = m.turn
    --a delve's chest: the delving hero's player rolls its dice, for all to
    --see, once per chest.
    if t.status == "chest" and t.userid == dmhub.loginUserid and t.delve ~= nil then
        if m_launchedRollSeq == t.rollSeq then
            return
        end
        m_launchedRollSeq = t.rollSeq
        local seq = t.rollSeq
        local delve = EncounterMontage.TurnDelve(t)
        local chestTable = delve ~= nil and delve.sections.chest ~= nil and delve.sections.chest.table or nil
        dmhub.Roll{
            roll = (chestTable ~= nil and chestTable.dice) or "1d6",
            description = string.format("%s: %s", t.delve.entryName or "Delve", (chestTable ~= nil and chestTable.name) or "Chest"),
            tokenid = t.heroid,
            complete = function(rollInfo)
                if mod.unloaded then
                    return
                end
                EncounterMontage.SendRequest("chestRolled", { rollSeq = seq, total = rollInfo.total })
            end,
        }
        return
    end
    --the test itself, or the assist someone stepped in with: whichever roll
    --is waiting on THIS user, at most once per rollSeq.
    local assisting = t.status == "assisting" and t.assist ~= nil and t.assist.userid == dmhub.loginUserid
    if not assisting and (t.status ~= "rolling" or t.userid ~= dmhub.loginUserid) then
        return
    end
    local rollSeq = assisting and t.assist.rollSeq or t.rollSeq
    if m_launchedRollSeq == rollSeq then
        return
    end
    local beat = EncounterMontage.CurrentBeat()
    if beat == nil then
        return
    end
    local entry = EncounterMontage.TurnEntry(beat, t)
    local option = entry ~= nil and entry.options[t.optionIndex or 0] or nil
    if option == nil or option.roll == nil then
        return
    end
    local rollerId = assisting and t.assist.heroid or t.heroid
    local heroToken = dmhub.GetCharacterById(rollerId)
    if heroToken == nil or not heroToken.valid then
        return
    end
    m_launchedRollSeq = rollSeq
    if assisting then
        LaunchAssistRoll(t, entry, option, heroToken)
    else
        LaunchRoll(t, entry, option, heroToken)
    end
end

--- dev driver ----------------------------------------------------------------------

--Outside a real EotW game there is no map-script host tick to run a
--montage, so "/eotwmontage start" runs one here: the first montage beat of
--the current map's script, ticked every 0.5s until it reports done.
local m_devDriver = nil

function EncounterMontage.StartDevDriver()
    if m_devDriver ~= nil and m_devDriver.running then
        print("EotW montage: dev driver already running")
        return
    end
    local driver = { running = true }
    m_devDriver = driver
    dmhub.Coroutine(function()
        while driver.running and not mod.unloaded do
            local script = EncounterMontage.FindMapScript()
            local beat, index = nil, nil
            for i, b in ipairs(script.parse.beats) do
                if b.kind == "montage" then
                    beat, index = b, i
                    break
                end
            end
            if beat == nil then
                print("EotW montage: this map's script has no montage beat")
                break
            end
            local ok, status = pcall(EncounterMontage.HostTick, script, beat, index)
            if not ok then
                printf("EotW montage: dev driver tick failed: %s", tostring(status))
            elseif status == "done" then
                print("EotW montage: montage complete (dev driver)")
                EncounterMontage.Hide()
                break
            end
            coroutine.yield(0.5)
        end
        driver.running = false
    end)
    print("EotW montage: dev driver started")
end

function EncounterMontage.StopDevDriver()
    if m_devDriver ~= nil then
        m_devDriver.running = false
        m_devDriver = nil
    end
end

--Full test reset (dev, host only in an EotW game): stop the dev driver,
--hide the stage, delete the montage's allies and the encounter beat's
--spawned monsters, clear the script/montage state, zero the malice pool,
--heal every hero to full, and in an EotW game clear the combat flags and
--detach the EotW map script -- the codemod's self-heal re-attaches it
--within a second with a fresh record, so its run-once watermarks and
--stage start clean and the script plays again from beat 1. Refuses while
--combat is running (end it first).
function EncounterMontage.ResetTest()
    EncounterMontage.StopDevDriver()
    EncounterMontage.Hide()

    local q = dmhub.initiativeQueue
    if q ~= nil and not q.hidden then
        print("EotW montage: combat is running; end combat first, then reset again")
        return false
    end

    local doc = EncounterMontage.GetDoc()

    --everything the script put on the map: montage allies (from the doc and
    --by their tag, in case the doc lost track) and the encounter's spawns.
    local toDelete = {}
    for _, list in pairs(doc.data.allies or {}) do
        if type(list) == "table" then
            for _, charid in ipairs(list) do
                toDelete[#toDelete + 1] = charid
            end
        end
    end
    for _, tok in ipairs(dmhub.allTokens) do
        if tok.valid and tok.properties ~= nil then
            local allyOf = nil
            pcall(function() allyOf = tok.properties:try_get("eotwAllyOf") end)
            if allyOf ~= nil then
                toDelete[#toDelete + 1] = tok.charid
            end
        end
    end
    local entry = nil
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw ~= nil and eotw.FindMapEncounter ~= nil then
        pcall(function() entry = eotw.FindMapEncounter() end)
    end
    if entry ~= nil then
        for _, charid in ipairs(entry.richEncounter:try_get("spawns", {})) do
            toDelete[#toDelete + 1] = charid
        end
    end

    ElevateToHostPermissions()
    local ok, err = pcall(function()
        local seen, list = {}, {}
        for _, charid in ipairs(toDelete) do
            if not seen[charid] and dmhub.GetCharacterById(charid) ~= nil then
                seen[charid] = true
                list[#list + 1] = charid
            end
        end
        if #list > 0 then
            game.DeleteCharacters(list)
            printf("EotW montage: removed %s", EncounterScript.Plural(#list, "spawned token"))
        end
        if entry ~= nil and #entry.richEncounter:try_get("spawns", {}) > 0 then
            entry.richEncounter.spawns = {}
            entry.richEncounter:UploadDocument()
        end
        CharacterResource.SetMalice(0, "Montage test reset")
        for _, hero in ipairs(EncounterMontage.Heroes()) do
            local token = hero.token
            token:ModifyProperties{
                description = "Montage test reset",
                undoable = false,
                execute = function()
                    token.properties.damage_taken = 0
                end,
            }
        end
        --a montage that surprised the party put the condition on them for
        --real; a reset has to take it off again.
        SetHeroesSurprised(false, "Montage test reset")
        --and a "you know the stamina of ..." outcome went into the shared
        --monster knowledge document; forget it too.
        local knowledge = rawget(_G, "MonsterKnowledge")
        if knowledge ~= nil and knowledge.ClearKeywordReveals ~= nil then
            knowledge.ClearKeywordReveals()
        end
        --placed trap objects come off the map and the trimmed/revealed
        --zones go back to how the author painted them.
        local zones = rawget(_G, "EncounterZones")
        if zones ~= nil and zones.ResetMap ~= nil then
            zones.ResetMap(doc)
        end
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW montage: reset cleanup failed: %s", tostring(err))
    end

    doc:BeginChange()
    doc.data.montage = nil
    doc.data.narrative = nil
    doc.data.stageDismissAt = nil
    doc.data.allies = nil
    doc.data.items = nil
    doc.data.beat = nil
    doc.data.initiative = nil
    doc.data.surges = nil
    doc.data.noSurprise = nil
    doc.data.surprised = nil
    doc.data.zoneSetup = nil
    doc.data.revealZones = nil
    doc.data.zonesRevealed = nil
    doc.data.unlocked = nil
    doc.data.intelligence = nil
    doc.data.intelligenceLog = nil
    doc.data.prep = nil
    doc:CompleteChange("Montage test reset", { undoable = false })

    --EotW game: the combat flags and the map script's run-once state.
    local state = mod:GetDocumentSnapshot("eotwstate")
    if state.data.combatStarted ~= nil or state.data.proceedRequested ~= nil then
        state:BeginChange()
        state.data.combatStarted = nil
        state.data.proceedRequested = nil
        state:CompleteChange("Montage test reset", { undoable = false })
    end
    local ms = rawget(_G, "MapScript")
    if ms ~= nil then
        local kept, removed = {}, false
        for _, rec in ipairs(ms.GetAttachedRecords()) do
            if rec.scriptid == "builtin:eotw-encounter" then
                removed = true
            else
                kept[#kept + 1] = rec
            end
        end
        if removed then
            ms.SetAttachedRecords(kept)
            print("EotW montage: the EotW map script was detached; it re-attaches fresh within a second and the script restarts from beat 1")
        end
    end

    print("EotW montage: test reset complete")
    return true
end

--- dev commands ------------------------------------------------------------------

--"/eotwscript": dump the current map's parsed script with its warnings and
--check every item and monster name against the game's tables.
pcall(function()
    Commands.RegisterMacro{
        name = "eotwscript",
        summary = "dump the Encounter of the Week script for this map",
        doc = "Usage: /eotwscript\nParses the current map's journal script (montage + encounter beats) and prints the result, warnings, and whether every item and monster name resolves.",
        command = function(str)
            local script = EncounterMontage.FindMapScript(true)
            local lines = {}
            lines[#lines + 1] = string.format("script document: %s", tostring(script.docid))
            for _, info in pairs(script.parse.included or {}) do
                lines[#lines + 1] = string.format("  includes: %s (%s)", tostring(info.name), tostring(info.id))
            end
            lines[#lines + 1] = EncounterScript.Describe(script.parse)
            local items, monsters = EncounterScript.ReferencedNames(script.parse)
            for name, _ in pairs(items) do
                local id = EncounterMontage.FindGear(name)
                lines[#lines + 1] = string.format("item '%s': %s", name, cond(id ~= nil, "found " .. tostring(id), "NOT FOUND"))
            end
            for name, _ in pairs(monsters) do
                local id = EncounterMontage.FindMonster(name)
                lines[#lines + 1] = string.format("monster '%s': %s", name, cond(id ~= nil, "found " .. tostring(id), "NOT FOUND"))
            end
            local text = table.concat(lines, "\n")
            print(text)
            pcall(function() chat.Send(text) end)
        end,
    }

    --"/eotwmontage reset|state": dev controls for the running montage.
    Commands.RegisterMacro{
        name = "eotwmontage",
        summary = "inspect or reset the Encounter of the Week montage",
        doc = "Usage: /eotwmontage start | stop | state | reset\nstart runs this map's montage right here (a dev host tick, for the authoring game); stop halts that driver; state prints the montage document; reset restarts the whole test: removes spawned allies and monsters, clears the script state, zeroes malice, heals the heroes, and in an EotW game re-arms the map script so the script plays again from the start.",
        command = function(str)
            local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
            if arg == "start" then
                EncounterMontage.StartDevDriver()
            elseif arg == "stop" then
                EncounterMontage.StopDevDriver()
                print("EotW montage: dev driver stopped")
            elseif arg == "reset" then
                EncounterMontage.ResetTest()
            else
                local doc = EncounterMontage.GetDoc()
                print(json(doc.data))
                local ok, script = pcall(EncounterMontage.FindMapScript)
                if ok and script ~= nil then
                    for _, b in ipairs(script.parse.beats) do
                        if b.kind == "montage" then
                            for _, l in ipairs(EncounterMontage.DescribeRemovals(b, doc.data.montage)) do
                                print(l)
                            end
                            for _, l in ipairs(EncounterMontage.DescribeLocks(b, doc.data.montage)) do
                                print(l)
                            end
                            for _, l in ipairs(EncounterMontage.DescribeTestMods(b, doc.data.montage)) do
                                print(l)
                            end
                            for _, l in ipairs(EncounterMontage.DescribeTemporary(b, doc.data.montage)) do
                                print(l)
                            end
                            break
                        end
                    end
                end
            end
        end,
    }
end)
