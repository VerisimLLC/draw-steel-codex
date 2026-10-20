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
--                   status = "scene"|"choosing"|"rolling"|"perk"|"pardon"|"dice"|"resolved",
--                   scene = { id, part = "intro"|"option"|"outcome",
--                             steps = { { kind = "narrate"|"say", text, speaker,
--                                         side = "left"|"right", lang, garbled,
--                                         plain (a garbled line's own words),
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
--                   status also "chest" (the chest's dice roll is out),
--                   "chestlanded" (the roll has landed; the hero clicks to
--                   take the find) and "delvechoice" (press deeper or turn
--                   back) inside a delve.
--                   chest = nil | { guids = { guid, ... }, mod, total, rowIndex,
--                                   newReveal, landedAt }
--                                           -- the chest roll in flight: its dice (so
--                                              every client can follow them), then
--                                              where it landed.
--                   optionIndex, rollSeq, tier, total, natural, applied = {...}, resolvedAt,
--                   attrid, skillid,        -- what the acting hero rolled with
--                   baseTier, baseTotal,    -- the test's result before any perk
--                   pardon = nil | { userid, heroid, heroName, rollSeq, startedAt },
--                   -- "pardon": another hero with Pardon My Friend is re-rolling
--                      the failed Presence test in the hero's place. }
--    dice = nil | { seq, purpose = "turn"|"consequence", entryName, entryId,
--                   tier, userid (turn: what ApplyResolution resumes with),
--                   consequenceIndex (consequence: which one it is for),
--                   rolls = { { key, kind = "table"|"recovery", dice, label,
--                               heroid, heroName, userid, total }, ... },
--                   openedAt }
--                  -- the dice a landed tier or a consequence needs before it
--                     applies ("roll on Flotsam", "loses 1d3 recoveries"):
--                     each is rolled on the screen by the player of its hero
--                     (EncounterMontage.ClientTick), then the effects apply
--                     with those totals (ApplyEffects' ctx.diceTotals). The
--                     turn waits in status "dice"; a consequence waits with
--                     its Continue hidden. DICE_ROLL_SECONDS rolls for anyone
--                     who never does.
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
--  data.startZones = nil | { [zone keyword, lower-cased] = { entryName, at } }
--                  -- "the Start2 zone becomes a starting area": extra zone
--                     types the heroes may stand in before combat (the
--                     start-zone confinement reads it).
--  data.revealObjects = nil | { [object name, lower-cased] = { name, entryName, at } }
--                  -- "reveal the Treasure Chest object", banked; the
--                     encounter beat switches those inactive objects on and
--                     moves the record to data.objectsRevealed.
--  data.surges   = nil | { [heroCharid] = n }
--                  -- surges banked by "at the start of the next combat you
--                     gain N surges", paid out (and cleared) by
--                     ApplyPendingCombatBoons when combat starts.
--  data.chestSeen = nil | { [delve MatchKey] = { ["lo-hi"] = true } }
--                  -- the rows of each delve's chest table the party has
--                     landed on; the rest read "???" (EncounterMontage.ChestRowSeen).
--                     Deliberately NOT cleared by a reset: what the party has
--                     learned about the treasure stays learned.
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
--how long a Pardon My Friend re-roll may sit unrolled and unaccepted (a
--client that closed the dialog without cancelling, or went away) before the
--hero's own roll stands. Generous: once the dice land the table may stop to
--talk (and ping) over whether to spend a hero token.
local PARDON_ROLL_SECONDS = 300
--how long a montage dice roll (a table roll, a hero's share of "loses 1d3
--recoveries") waits on its player before the host rolls it for them.
local DICE_ROLL_SECONDS = 45

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

--What the stage shows beside a hero's card: the montage haul in grant
--order, then every other consumable the hero carries -- items brought from
--town can be used in a montage too (user direction 2026-10-09).
--{ { itemid, name, qty, haul }, ... }; `haul` = gained in this montage
--(only those can be handed to another hero). A consumable's qty is what the
--hero really holds, so a used one shrinks or leaves at once.
function EncounterMontage.GetStripItems(heroid)
    local result, seen = {}, {}
    local tok = dmhub.GetCharacterById(heroid)
    local props = (tok ~= nil and tok.valid) and tok.properties or nil
    local valid = props ~= nil
    local gear = dmhub.GetTable("tbl_Gear") or {}
    local function Held(itemid)
        local qty = 0
        if props ~= nil then
            pcall(function() qty = props:GetItemQuantity(itemid) end)
        end
        return qty
    end
    for _, entry in ipairs(EncounterMontage.GetItems(heroid)) do
        seen[entry.itemid] = true
        local item = gear[entry.itemid]
        local qty = entry.qty or 1
        if valid and item ~= nil and EquipmentCategory.IsConsumable(item) then
            --carried copies of the same item ride on the haul's icon.
            qty = Held(entry.itemid)
        end
        if qty > 0 then
            result[#result + 1] = { itemid = entry.itemid, name = entry.name, qty = qty, haul = true }
        end
    end
    if props ~= nil then
        local carried = {}
        pcall(function()
            for itemid, info in pairs(props:try_get("inventory", {})) do
                local item = gear[itemid]
                local qty = type(info) == "table" and tonumber(info.quantity) or 0
                if not seen[itemid] and item ~= nil and (qty or 0) > 0 and EquipmentCategory.IsConsumable(item) then
                    carried[#carried + 1] = { itemid = itemid, name = item.name, qty = qty, haul = false }
                end
            end
        end)
        table.sort(carried, function(a, b)
            if a.name ~= b.name then
                return tostring(a.name) < tostring(b.name)
            end
            return a.itemid < b.itemid
        end)
        for _, entry in ipairs(carried) do
            result[#result + 1] = entry
        end
    end
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

--Per-hero Intelligence. data.intelligenceByHero = { [charid] = n } is what
--each hero earned and has not spent yet; data.intelligence stays the party
--TOTAL (what the pools strip shows), so the two are only ever written
--together, by CreditIntelligence and SpendIntelligence below. Any part of
--the total no hero holds (Intelligence earned before per-hero tracking, or
--with no heroes on the map) is "shared": any player may spend it.
function EncounterMontage.GetHeroIntelligence(charid)
    local n = 0
    pcall(function()
        local byHero = mod:GetDocumentSnapshot(DOC_ID).data.intelligenceByHero
        if type(byHero) == "table" then
            n = tonumber(byHero[charid]) or 0
        end
    end)
    return n
end

--The shared part of the total (see above). `data` is a snapshot's or an
--OPEN document's data table; nil reads the current snapshot.
function EncounterMontage.SharedIntelligence(data)
    local n = 0
    pcall(function()
        data = data or mod:GetDocumentSnapshot(DOC_ID).data
        local held = 0
        for _, amount in pairs(data.intelligenceByHero or {}) do
            held = held + (tonumber(amount) or 0)
        end
        n = math.max(0, (tonumber(data.intelligence) or 0) - held)
    end)
    return n
end

--What a player running the heroes `heroids` may spend: those heroes' own
--Intelligence plus the shared part. `data` as for SharedIntelligence.
function EncounterMontage.SpendableIntelligence(heroids, data)
    local n = 0
    pcall(function()
        data = data or mod:GetDocumentSnapshot(DOC_ID).data
        local byHero = data.intelligenceByHero or {}
        for _, charid in ipairs(heroids or {}) do
            n = n + (tonumber(byHero[charid]) or 0)
        end
    end)
    return n + EncounterMontage.SharedIntelligence(data)
end

--Host, inside an OPEN change on the script document: change heroes'
--Intelligence and the party total with them. credits = { { charid, name,
--qty }, ... }; a negative qty is a loss, which never takes a hero below 0.
--sharedQty (optional) goes to the total with no hero holding it. Writes one
--history line for the strip's tooltip, naming who earned what.
function EncounterMontage.CreditIntelligence(doc, credits, who, note, sharedQty)
    local byHero = doc.data.intelligenceByHero or {}
    local before = tonumber(doc.data.intelligence) or 0
    local delta = sharedQty or 0
    local parts = {}
    for _, credit in ipairs(credits or {}) do
        local have = tonumber(byHero[credit.charid]) or 0
        local change = math.max(tonumber(credit.qty) or 0, -have)
        if change ~= 0 then
            byHero[credit.charid] = cond(have + change > 0, have + change, nil)
            delta = delta + change
            parts[#parts + 1] = string.format("%s %+d", tostring(credit.name), change)
        end
    end
    doc.data.intelligenceByHero = byHero
    if delta == 0 then
        return 0
    end
    doc.data.intelligence = math.max(0, before + delta)
    local log = doc.data.intelligenceLog or {}
    if #parts > 0 then
        note = string.format("%s (%s)", tostring(note), table.concat(parts, ", "))
    end
    log[#log + 1] = {
        value = doc.data.intelligence,
        amount = delta,
        who = who,
        note = note,
        at = dmhub.serverTime,
    }
    doc.data.intelligenceLog = log
    return delta
end

--Intelligence no single hero earned (a consequence, a choice the party
--agreed on), divided evenly across `heroes`. The odd points go to whoever
--holds the least (a loss: the most), ties in roster order. Returns credits
--for CreditIntelligence.
function EncounterMontage.SplitIntelligence(doc, heroes, qty)
    local credits = {}
    if #heroes == 0 or qty == 0 then
        return credits
    end
    local byHero = doc.data.intelligenceByHero or {}
    local sign = cond(qty < 0, -1, 1)
    local amount = math.abs(qty)
    local base = math.floor(amount / #heroes)
    local remainder = amount - base * #heroes
    local order = {}
    for i, hero in ipairs(heroes) do
        credits[i] = { charid = hero.charid, name = hero.name, qty = sign * base }
        order[i] = { index = i, have = tonumber(byHero[hero.charid]) or 0 }
    end
    table.sort(order, function(a, b)
        if a.have ~= b.have then
            return cond(sign > 0, a.have < b.have, a.have > b.have)
        end
        return a.index < b.index
    end)
    for i = 1, remainder do
        local credit = credits[order[i].index]
        credit.qty = credit.qty + sign
    end
    return credits
end

--Host, inside an OPEN change: take `qty` Intelligence off the player who
--runs `heroids` -- from their hero holding the most each point (ties in the
--order given), then from the shared part. Returns false when they do not
--have it; true and the names it came from otherwise. Writes no history line
--(the caller knows what it was spent on).
function EncounterMontage.SpendIntelligence(doc, heroids, qty, names)
    if EncounterMontage.SpendableIntelligence(heroids, doc.data) < qty then
        return false
    end
    local byHero = doc.data.intelligenceByHero or {}
    local from = {}
    for _ = 1, qty do
        local best, bestHave = nil, 0
        for _, charid in ipairs(heroids or {}) do
            local have = tonumber(byHero[charid]) or 0
            if have > bestHave then
                best, bestHave = charid, have
            end
        end
        if best ~= nil then
            byHero[best] = cond(bestHave > 1, bestHave - 1, nil)
            from[#from + 1] = (names or {})[best] or best
        else
            from[#from + 1] = "the party"
        end
    end
    doc.data.intelligenceByHero = byHero
    doc.data.intelligence = math.max(0, (tonumber(doc.data.intelligence) or 0) - qty)
    return true, from
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
--The markdown documents filed under a map's journal folder, sorted by name:
--the candidates for its script. Returns a list of { docid, doc }.
local function MapScriptCandidates(mapid)
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
    return candidates
end

--Which part of a series the game is playing (EncounterOfTheWeekGame.ActivePart:
--the part in the game's encounter key, or the one an authoring test picked).
--1 when nothing says otherwise, which is also every map that is not a series.
local function ActivePart()
    local part = 1
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw ~= nil and eotw.ActivePart ~= nil then
        pcall(function() part = eotw.ActivePart() end)
    end
    return math.floor(tonumber(part) or 1)
end
EncounterMontage.ActivePart = ActivePart

--Parse every candidate and pick the map's script: the first (by name) that
--declares beats and is not part of another, preferring an explicit one.
--A map whose scripts say "# Part N" is a SERIES: each part is its own
--script and `part` picks which one plays (nil best when it has no such part;
--documents without a part heading are then notes, never the script).
--Returns best (nil if none), allIncluded ({docid -> true}), parts (the
--series' part scripts sorted by number then name; empty when not a series).
local function ChooseMapScript(candidates, mapid, part)
    local loaded = {}
    local allIncluded = {}
    for _, c in ipairs(candidates) do
        local script = EncounterMontage.LoadScript(c.docid, mapid)
        loaded[#loaded + 1] = script
        for docid in pairs(script ~= nil and script.parse.included or {}) do
            allIncluded[docid] = true
        end
    end

    local parts = {}
    for _, script in ipairs(loaded) do
        if script ~= nil and not allIncluded[script.docid] and script.parse.part ~= nil then
            parts[#parts + 1] = script
        end
    end
    if #parts > 0 then
        --stable: candidates are already in name order.
        table.sort(parts, function(a, b)
            if a.parse.part.number ~= b.parse.part.number then
                return a.parse.part.number < b.parse.part.number
            end
            return (a.doc.description or "") < (b.doc.description or "")
        end)
        local best = nil
        for _, script in ipairs(parts) do
            if script.parse.part.number == part and #script.parse.beats > 0 then
                best = script
                break
            end
        end
        return best, allIncluded, parts
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
    return best, allIncluded, parts
end

--{ {number, title}, ... } for a series' part scripts (see ChooseMapScript).
local function PartSummaries(parts)
    local result = {}
    for _, script in ipairs(parts or {}) do
        result[#result + 1] = { number = script.parse.part.number, title = script.parse.part.title }
    end
    return result
end

--The script of any map in the game, not just the current one, for the
--publish dialog's Encounter of the Week module type (ModShare.lua). Uncached
--and with no info-bubble fallback (that reads the current map only).
--Returns { script = { docid, doc, parse, text } or nil, documents = {docid ->
--true}, parts }, documents being every document the script could be built
--from: the map's journal documents and everything they include. For a
--series, script is part 1's and parts lists every part's script (sorted by
--number; a repeated number appears twice so the publisher can refuse it).
function EncounterMontage.ScriptForMap(mapid)
    local candidates = MapScriptCandidates(mapid)
    local best, allIncluded, parts = ChooseMapScript(candidates, mapid, 1)
    local documents = {}
    for _, c in ipairs(candidates) do
        documents[c.docid] = true
    end
    for docid in pairs(allIncluded) do
        documents[docid] = true
    end
    return { script = best, documents = documents, parts = parts }
end

function EncounterMontage.FindMapScript(force)
    local mapid = game.currentMapId
    local docsTable = dmhub.GetTable("documents") or {}
    local candidates = MapScriptCandidates(mapid)
    local part = ActivePart()

    if m_scriptCache ~= nil and not force and m_scriptCache.docid ~= nil and m_scriptCache.mapid == mapid
        and m_scriptCache.part == part
        and m_scriptCache.signature == ScriptSignature(candidates, m_scriptCache.allIncluded) then
        if m_scriptCache.docid ~= nil then
            m_scriptCache.doc = docsTable[m_scriptCache.docid] or m_scriptCache.doc
        end
        return m_scriptCache
    end

    local best, allIncluded, parts = ChooseMapScript(candidates, mapid, part)

    if best == nil and #parts > 0 then
        --a series with no script for this part: nothing to play (and no
        --info-bubble fallback, which would play some other part's fight).
        printf("EotW: this map is a series but has no script for part %d", part)
        best = { docid = nil, doc = nil, parse = { beats = {}, warnings = {}, hasEncounterTag = false }, text = "" }
    elseif best == nil then
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
    best.part = part
    --{ {number, title}, ... } when the map is a series, else empty.
    best.seriesParts = PartSummaries(parts)
    best.allIncluded = allIncluded
    best.signature = ScriptSignature(candidates, allIncluded)
    m_scriptCache = best
    return best
end

--The documents the current script is made of (its own and every document
--it includes), as {docid -> true}; empty when the map has no script
--document. Where a series' encounter islands are looked for.
function EncounterMontage.ScriptDocuments(script)
    local result = {}
    if script == nil or script.docid == nil then
        return result
    end
    result[script.docid] = true
    for docid in pairs(script.parse.included or {}) do
        result[docid] = true
    end
    return result
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
                --the scene's "Art by" setting: the stage badges credited art.
                CreatorCredit.TagSceneArt(img, tag:GetCredit())
            end
        end
    end)
    return image
end

--A montage's backdrop for a round: the [[scene]] under the latest "## Round
--N" heading at or before `round` that names one (so a day scene for round 1
--and a night scene for round 2), else the beat's own first scene.
function EncounterMontage.MontageSceneImage(script, beat, round)
    if beat == nil then
        return nil
    end
    round = tonumber(round) or 1
    local best = nil
    for _, r in ipairs(beat.rounds or {}) do
        if r.sceneTag ~= nil and r.number <= round and (best == nil or r.number > best.number) then
            best = r
        end
    end
    if best ~= nil then
        local image = EncounterMontage.SceneImage(script, best)
        if image ~= nil then
            return image
        end
    end
    return EncounterMontage.SceneImage(script, beat)
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

--Does the local user drive this hero? (UI gates; the host re-checks with
--UserControlsHero.)
local function LocalControlsHero(heroid)
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

EncounterMontage.LocalControlsHero = LocalControlsHero

--Can the local user drag this hero right now? (UI gate; the host re-checks.)
function EncounterMontage.LocalUserCanAct(heroid)
    local m = EncounterMontage.GetState()
    if m == nil or m.phase ~= "rounds" or not EncounterMontage.TurnOver(m) then
        return false
    end
    if (m.acted or {})[heroid] then
        return false
    end
    return LocalControlsHero(heroid)
end

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
--`round` is the montage's current round, for "|Edge (Round 1): ..." riders.
--Reading a hero's facts walks their features, abilities and choices, and
--the stage asks for every option it draws, so they are cached for a moment
--per hero. A copy is returned: callers add `round`.
local g_factsCache = {}
local FACTS_CACHE_SECONDS = 2
--Facts to use for a hero in place of their real ones while an item is being
--tried on ("what an item could do for the test at hand", below).
local g_factsOverride = {}

function EncounterMontage.HeroFacts(charid)
    local now = dmhub.Time()
    local cached = g_factsCache[charid or ""]
    --an item used in the montage can change a hero's facts (a language, a
    --flight speed), so a use (consumeSeq) retires the cache.
    local consumeSeq = nil
    pcall(function() consumeSeq = (EncounterMontage.GetState() or {}).consumeSeq end)
    local base = g_factsOverride[charid or ""]
    if base ~= nil then
        --being tried on: never cached.
    elseif cached ~= nil and now < cached.expires and cached.consumeSeq == consumeSeq then
        base = cached.facts
    else
        local tok = dmhub.GetCharacterById(charid)
        if tok == nil or not tok.valid or tok.properties == nil then
            base = TestRiders.CompleteFacts({})
        else
            base = TestRiders.CreatureFacts(tok.properties)
        end
        g_factsCache[charid or ""] = { facts = base, expires = now + FACTS_CACHE_SECONDS, consumeSeq = consumeSeq }
    end
    local facts = {}
    for k, v in pairs(base) do
        facts[k] = v
    end
    pcall(function()
        local m = EncounterMontage.GetState()
        if m ~= nil then
            facts.round = m.round or 1
        end
    end)
    return facts
end

--Does this hero meet a requirement? Returns met and why (the clause that
--met it).
local function HeroRequirementMet(charid, req)
    local met, why = false, nil
    pcall(function() met, why = EncounterScript.RequirementMet(req, EncounterMontage.HeroFacts(charid)) end)
    return met == true, why
end

--The first knack of `option` that this hero meets and that has a roll or
--rules, as an index into option.knacks; nil when none.
function EncounterMontage.KnackIndex(charid, option)
    if option == nil or option.knacks == nil or #option.knacks == 0 or option.delve ~= nil then
        return nil
    end
    for i, k in ipairs(option.knacks) do
        if EncounterScript.KnackUsable(k) and HeroRequirementMet(charid, k.requirement) then
            return i
        end
    end
    return nil
end

--Why this hero gets a knack ("you can fly (Wings)"), or nil.
function EncounterMontage.KnackReason(charid, option, knackIndex)
    local k = option ~= nil and option.knacks ~= nil and knackIndex ~= nil and option.knacks[knackIndex] or nil
    if k == nil then
        return nil
    end
    local met, why = HeroRequirementMet(charid, k.requirement)
    if not met then
        return k.requirementText
    end
    return why or k.requirementText
end

--The version of `option` this hero takes: the first knack they meet, or the
--option itself.
function EncounterMontage.OptionForHero(charid, option)
    return EncounterScript.OptionVersion(option, EncounterMontage.KnackIndex(charid, option))
end

--The option the turn in flight is taking, in the version the host fixed
--when it was chosen (t.knackIndex).
function EncounterMontage.TurnOption(entry, t)
    if entry == nil or t == nil then
        return nil
    end
    local option = entry.options[t.optionIndex or 0]
    if option == nil then
        return nil
    end
    return EncounterScript.OptionVersion(option, t.knackIndex)
end

--The turn's option as written (no knack applied), for the host's gate.
function EncounterMontage.TurnBaseOption(entry, t)
    if entry == nil or t == nil then
        return nil
    end
    return entry.options[t.optionIndex or 0]
end

--The effects a version of an option applies at `tierIndex`: its roll's
--tier, or -- for a free version (tier 0) -- its rules.
function EncounterMontage.VersionEffects(option, tierIndex)
    if option == nil then
        return {}
    end
    if option.roll ~= nil and tierIndex ~= nil and tierIndex > 0 then
        return option.roll.effects[tierIndex] or {}
    end
    if option.free ~= nil then
        return option.free.effects or {}
    end
    return {}
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
--`version` is the version of the option the hero takes (a knack's, or the
--option itself); nil works it out (OptionForHero). The option's Allow
--lines decide whether the hero may take it at all; a knack's roll brings
--its own edges, not the base roll's.
function EncounterMontage.RiderVerdict(charid, option, version)
    if option == nil then
        return nil
    end
    --a version passed in is a copy carrying .knack; get back to the option
    --as written for its Allow lines.
    if version == nil then
        version = EncounterMontage.OptionForHero(charid, option)
    end
    local riders = EncounterScript.VersionRiders(option, version)
    local granted = {}
    if version.roll ~= nil then
        granted = EncounterMontage.OptionTestMods(nil, option)
    end
    if #riders == 0 and #granted == 0 then
        return nil
    end
    local facts = EncounterMontage.HeroFacts(charid)
    --Declared with a type instead of initialized to nil: the checker would
    --otherwise infer `nil` from the declaration and flag every field read
    --below, since the pcall closure is what actually fills it in.
    ---@type table
    local verdict
    local ok, err = pcall(function()
        verdict = EncounterScript.EvaluateRiders(riders, facts)
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

--May this hero see (and take) this option? A secret option -- one an
--Allow / Secret rider gates -- is invisible to a hero who does not meet it.
--Everyone watching the stage sees the options of the hero at the entry,
--so a secret option appears for spectators exactly when it appears for
--the player choosing.
function EncounterMontage.OptionVisible(charid, option)
    if option == nil then
        return false
    end
    if not EncounterScript.OptionIsSecret(option) then
        return true
    end
    local verdict = EncounterMontage.RiderVerdict(charid, option, nil)
    return verdict == nil or verdict.allowed
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

--The listed skills a hero is trained in, as a set ({ [skillid] = true }).
--Team Leader's lent exploration skills count.
local function TrainedSkillSet(charid, skills)
    local set = {}
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid or tok.properties == nil then
        return set
    end
    local skillTable = dmhub.GetTable(Skill.tableName) or {}
    for _, skillid in ipairs(skills) do
        local skillInfo = skillTable[skillid]
        if skillInfo ~= nil then
            local trained = false
            pcall(function() trained = tok.properties:ProficientInSkill(skillInfo) end)
            if trained or EncounterMontage.TeamLeaderGrants(skillid) then
                set[skillid] = true
            end
        end
    end
    return set
end

--The listed skill the hero making the turn's test rolls with: the first
--they are trained in (nil for none).
function EncounterMontage.MainTestSkill(t, option)
    local listed = EncounterMontage.OptionSkills(option)
    return EncounterScript.MainTestSkill(listed, TrainedSkillSet(t.heroid, listed))
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
    --LocalUserPacesScene is false when m is nil.
    ---@cast m -nil
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

--The ongoing effect behind "your rolled damage is increased by N": a power
--roll modifier that adds N to the damage of every damaging power roll, the
--same shape as a kit's or a treasure's rolled-damage bonus. One asset per
--value, reused, like the Recovery Value boon.
local function EnsureDamageBoonEffect(amount)
    local name = string.format("Montage Boon: Rolled Damage +%d", amount)
    local t = dmhub.GetTable("characterOngoingEffects") or {}
    for id, effect in pairs(t) do
        if NameMatches(effect.name, name) then
            return id
        end
    end
    local effect = CharacterOngoingEffect.Create{
        name = name,
        source = "Montage",
        description = string.format("You gain a +%d bonus to rolled damage.", amount),
        custom = true,
    }
    local modifier = CharacterModifier.new{
        behavior = "power",
        name = name,
        source = "Montage",
        description = string.format("+%d to rolled damage.", amount),
        guid = dmhub.GenerateGuid(),
        domains = {},
    }
    CharacterModifier.TypeInfo.power.init(modifier)
    modifier.rollType = "ability_power_roll"
    modifier.modtype = "none"
    modifier.activationCondition = true
    modifier.damageModifier = tostring(amount)
    effect.modifiers = { modifier }
    return dmhub.SetAndUploadTableItem("characterOngoingEffects", effect)
end

--The ongoing effect behind "your maximum Stamina is reduced by N": a plain
--attribute modifier on the Stamina maximum.
local function EnsureMaxStaminaCurseEffect(amount)
    local name = string.format("Montage Curse: Stamina Maximum -%d", amount)
    local t = dmhub.GetTable("characterOngoingEffects") or {}
    for id, effect in pairs(t) do
        if NameMatches(effect.name, name) then
            return id
        end
    end
    local effect = CharacterOngoingEffect.Create{
        name = name,
        source = "Montage",
        description = string.format("Your Stamina maximum is reduced by %d.", amount),
        custom = true,
    }
    effect.modifiers = {
        CharacterModifier.new{
            behavior = "attribute",
            attribute = "hitpoints",
            operation = "add",
            value = -amount,
            name = name,
            source = "Montage",
            guid = dmhub.GenerateGuid(),
        },
    }
    return dmhub.SetAndUploadTableItem("characterOngoingEffects", effect)
end

--The ongoing effect behind "you gain poison immunity 2": damage immunity N
--to one damage type, the same resistance modifier a treasure's immunity uses.
local function EnsureImmunityBoonEffect(damageType, amount)
    local name = string.format("Montage Boon: %s Immunity %d", damageType:sub(1, 1):upper() .. damageType:sub(2), amount)
    local t = dmhub.GetTable("characterOngoingEffects") or {}
    for id, effect in pairs(t) do
        if NameMatches(effect.name, name) then
            return id
        end
    end
    local effect = CharacterOngoingEffect.Create{
        name = name,
        source = "Montage",
        description = string.format("You have %s immunity %d.", damageType, amount),
        custom = true,
    }
    effect.modifiers = {
        CharacterModifier.new{
            behavior = "resistance",
            name = name,
            source = "Montage",
            guid = dmhub.GenerateGuid(),
            resistances = {
                ResistanceEntry.new{
                    apply = "Damage Reduction",
                    damageType = damageType,
                    dr = amount,
                },
            },
        },
    }
    return dmhub.SetAndUploadTableItem("characterOngoingEffects", effect)
end

--Put one of the montage's ongoing effects on a hero until the next respite.
--Same cache caveat as the Recovery Value boon (see GrantRecoveryBoon).
local function ApplyMontageEffect(token, effectid, description)
    if effectid == nil then
        return false
    end
    if GetTableCached("characterOngoingEffects")[effectid] == nil then
        printf("EotW montage: '%s' is not visible to the rules engine yet; '%s' was not applied", effectid, description)
        return false
    end
    token:ModifyProperties{
        description = description,
        undoable = false,
        execute = function()
            token.properties:ApplyOngoingEffect(effectid, "until_rest", nil, {})
        end,
    }
    return true
end

--"You lose a consumable": one consumable (by EquipmentCategory) picked at
--random from the hero's inventory goes. A hero carrying none loses a
--Recovery instead, and the party is told only of the Recovery. Returns the
--item name lost (or nil) and the number of recoveries lost.
local function LoseConsumable(token, note)
    local gear = dmhub.GetTable("tbl_Gear") or {}
    local candidates = {}
    pcall(function()
        local inventory = token.properties:try_get("inventory", {})
        for itemid, entry in pairs(inventory) do
            local item = gear[itemid]
            if item ~= nil and type(entry) == "table" and (tonumber(entry.quantity) or 0) > 0
                and EquipmentCategory.IsConsumable(item) then
                candidates[#candidates + 1] = { itemid = itemid, name = item.name, quantity = entry.quantity }
            end
        end
    end)
    if #candidates == 0 then
        return nil, LoseRecoveries(token, 1, note)
    end
    table.sort(candidates, function(a, b) return a.itemid < b.itemid end)
    local pick = candidates[math.random(1, #candidates)]
    token:ModifyProperties{
        description = string.format("Montage: lose %s", pick.name),
        undoable = false,
        execute = function()
            token.properties:SetItemQuantity(pick.itemid, pick.quantity - 1)
        end,
    }
    return pick, 0
end

--Roll a plain dice expression ("1d6", "2d6", "d8") on the host.
local function RollDiceExpression(dice)
    local count, sides = string.match(string.lower(dice or ""), "^(%d*)d(%d+)$")
    count = tonumber(count) or 1
    sides = tonumber(sides) or 6
    local total = 0
    for _ = 1, math.max(1, count) do
        total = total + math.random(1, math.max(1, sides))
    end
    return total
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
    local damageAmounts = {}
    local staminaAmounts = {}
    local immunities = {}
    local any = false
    local function Collect(effects)
        for _, effect in ipairs(effects or {}) do
            if effect.kind == "recovery" then
                amounts[effect.qty] = true
                any = true
            elseif effect.kind == "damageboon" then
                damageAmounts[effect.qty] = true
                any = true
            elseif effect.kind == "maxstamina" then
                staminaAmounts[effect.qty] = true
                any = true
            elseif effect.kind == "immunityboon" then
                immunities[effect.damageType .. ":" .. tostring(effect.qty)] = effect
                any = true
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
        for _, tableRoll in pairs(entry.tables or {}) do
            for _, row in ipairs(tableRoll.rows or {}) do
                Collect(row.effects)
            end
        end
    end
    if not any then
        return
    end

    ElevateToHostPermissions()
    local ok, err = pcall(function()
        for amount, _ in pairs(amounts) do
            EnsureRecoveryBoonEffect(amount)
        end
        for amount, _ in pairs(damageAmounts) do
            EnsureDamageBoonEffect(amount)
        end
        for amount, _ in pairs(staminaAmounts) do
            EnsureMaxStaminaCurseEffect(amount)
        end
        for _, effect in pairs(immunities) do
            EnsureImmunityBoonEffect(effect.damageType, effect.qty)
        end
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW montage: boon asset setup failed: %s", tostring(err))
    end
end

local function SpawnAlly(monsterid, heroEntry, userid)
    local loc = FreeTileNear(heroEntry.token)
    --FreeTileNear's tiles are x/y only: stand the ally on the ground there.
    local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, { fitLocation = true, onGround = true })
    if token == nil then
        return nil
    end
    pcall(function()
        --a bestiary spawn's properties are a monster.
        local props = token.properties --[[@as monster]]
        props:OnCreateFromBestiary(token, dmhub.GenerateGuid())
    end)
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
--(the state table being mutated), entryId, entry (the parsed entry, whose
--dice tables a "roll on <table>" clause rolls), doc (the script document,
--inside an open change, for effects that outlive the beat),
--splitIntelligence (true: Intelligence is split across the party instead of
--credited to heroEntry -- an agreed narrative choice) }. Returns the list of
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

    --dice the players rolled for this pass (EncounterMontage.PendingDice
    --names the keys); anything without one is rolled here.
    local diceTotals = ctx.diceTotals or {}

    ElevateToHostPermissions()
    local ok, err = pcall(function()
        for effectIndex, effect in ipairs(effects or {}) do
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
                    --FindGear returns the item alongside any id it finds.
                    ---@cast item -nil
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
                    --"loses 1d3 recoveries": each hero rolls their own.
                    local count = effect.qty
                    if effect.dice ~= nil then
                        count = tonumber(diceTotals[string.format("r:%d:%s", effectIndex, target.charid)])
                            or RollDiceExpression(effect.dice)
                    end
                    local callOk, lost = pcall(LoseRecoveries, target.token, count, SourceLabel(ctx))
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
                --the party's Intelligence pool, credited to the heroes who
                --earned it (each spends their own on Tactical Preparation).
                --It is ours, not a CharacterResource, so it is kept on the
                --script document (CreditIntelligence). One hero's test is
                --theirs; every hero who took a narrative option gets the
                --full amount; with no hero behind it (a consequence, or a
                --choice the party agreed on -- ctx.splitIntelligence) it is
                --split evenly across the party.
                if ctx.doc == nil then
                    printf("EotW montage: no script document open; '%s' not applied", tostring(effect.text))
                else
                    local targets = Targets(effect)
                    local split = ctx.splitIntelligence == true or #targets == 0
                    local credits = {}
                    if split then
                        credits = EncounterMontage.SplitIntelligence(ctx.doc, heroes, effect.qty)
                    else
                        for _, target in ipairs(targets) do
                            credits[#credits + 1] = { charid = target.charid, name = target.name, qty = effect.qty }
                        end
                    end
                    --no heroes on the map at all: it still lands, shared.
                    local shared = cond(#credits == 0, effect.qty, 0)
                    EncounterMontage.CreditIntelligence(ctx.doc, credits,
                        ctx.entryName or "Encounter of the Week", SourceLabel(ctx), shared)
                    local amountText = EncounterScript.Plural(effect.qty, "Intelligence", "Intelligence")
                    if split then
                        applied[#applied + 1] = string.format("+%s, shared among the party", amountText)
                    else
                        local names = {}
                        for _, target in ipairs(targets) do
                            names[#names + 1] = target.name
                        end
                        applied[#applied + 1] = string.format("%s %s", Subject(names, "gains", "gain"), amountText)
                    end
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
                    --FindMonster returns the asset alongside any id it finds.
                    ---@cast asset -nil
                    applied[#applied + 1] = string.format("%s cannot join: no hero", asset.name)
                else
                    ---@cast asset -nil
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
            elseif effect.kind == "rolltable" then
                --"Roll twice on Tinkerer's Wares": the entry's own dice
                --table, rolled here on the host, each row applied as if it
                --were written in the tier. A row may not roll again (depth).
                local tableRoll = ctx.entry ~= nil and (ctx.entry.tables or {})[effect.key] or nil
                if tableRoll == nil then
                    applied[#applied + 1] = string.format("No table '%s' to roll on", tostring(effect.name))
                elseif (ctx.tableDepth or 0) >= 2 then
                    printf("EotW montage: '%s' rolls on a table from inside a table roll; ignored", tostring(effect.text))
                else
                    for n = 1, effect.qty do
                        local total = tonumber(diceTotals[string.format("t:%d:%d", effectIndex, n)])
                            or RollDiceExpression(tableRoll.dice)
                        local row = EncounterScript.ChestRow(tableRoll, total)
                        applied[#applied + 1] = string.format("%s: rolled %d", tableRoll.name, total)
                        if row ~= nil then
                            local subCtx = {}
                            for k, v in pairs(ctx) do
                                subCtx[k] = v
                            end
                            subCtx.tableDepth = (ctx.tableDepth or 0) + 1
                            --the row's own clauses count from 1 again.
                            subCtx.diceTotals = nil
                            local rowApplied, rowAllies = EncounterMontage.ApplyEffects(row.effects, subCtx)
                            for _, text in ipairs(rowApplied) do
                                applied[#applied + 1] = text
                            end
                            for _, charid in ipairs(rowAllies) do
                                newAllies[#newAllies + 1] = charid
                            end
                        end
                    end
                end
            elseif effect.kind == "damageboon" then
                local names = {}
                local effectid = EnsureDamageBoonEffect(effect.qty)
                for _, target in ipairs(Targets(effect)) do
                    local grantOk, granted = pcall(ApplyMontageEffect, target.token, effectid,
                        string.format("Montage: rolled damage +%d", effect.qty))
                    if grantOk and granted then
                        names[#names + 1] = target.name
                    end
                end
                if effect.target == "party" then
                    applied[#applied + 1] = string.format("Every hero gains +%d to rolled damage until the next respite", effect.qty)
                elseif #names > 0 then
                    applied[#applied + 1] = string.format("%s +%d to rolled damage until the next respite", Subject(names, "gains", "gain"), effect.qty)
                end
            elseif effect.kind == "immunityboon" then
                local names = {}
                local effectid = EnsureImmunityBoonEffect(effect.damageType, effect.qty)
                for _, target in ipairs(Targets(effect)) do
                    local grantOk, granted = pcall(ApplyMontageEffect, target.token, effectid,
                        string.format("Montage: %s immunity %d", effect.damageType, effect.qty))
                    if grantOk and granted then
                        names[#names + 1] = target.name
                    end
                end
                if effect.target == "party" then
                    applied[#applied + 1] = string.format("Every hero gains %s immunity %d until the next respite", effect.damageType, effect.qty)
                elseif #names > 0 then
                    applied[#applied + 1] = string.format("%s %s immunity %d until the next respite", Subject(names, "gains", "gain"), effect.damageType, effect.qty)
                end
            elseif effect.kind == "maxstamina" then
                local names = {}
                local effectid = EnsureMaxStaminaCurseEffect(effect.qty)
                for _, target in ipairs(Targets(effect)) do
                    local grantOk, granted = pcall(ApplyMontageEffect, target.token, effectid,
                        string.format("Montage: Stamina maximum -%d", effect.qty))
                    if grantOk and granted then
                        names[#names + 1] = target.name
                    end
                end
                if effect.target == "party" then
                    applied[#applied + 1] = string.format("Every hero's Stamina maximum is reduced by %d until the next respite", effect.qty)
                elseif #names > 0 then
                    applied[#applied + 1] = string.format("%s: Stamina maximum -%d until the next respite", TargetNames(names), effect.qty)
                end
            elseif effect.kind == "loseconsumable" then
                --a hero with no consumable loses a Recovery instead, and the
                --line says only that: the swap is not announced.
                for _, target in ipairs(Targets(effect)) do
                    for _ = 1, effect.qty do
                        local callOk, lostItem, lostRecoveries = pcall(LoseConsumable, target.token, SourceLabel(ctx))
                        if callOk and lostItem ~= nil then
                            pcall(UnrecordItem, ctx.doc, target.charid, lostItem.itemid, 1)
                            applied[#applied + 1] = string.format("%s loses a %s", target.name, lostItem.name)
                        elseif callOk and (lostRecoveries or 0) > 0 then
                            applied[#applied + 1] = string.format("%s loses 1 Recovery", target.name)
                        end
                    end
                end
            elseif effect.kind == "startzone" then
                --banked on the document; the start-zone confinement reads it
                --(EncounterOfTheWeekGame.StartZoneLocs), and the encounter
                --beat reveals the zone to the players.
                if ctx.doc ~= nil then
                    ctx.doc.data.startZones = ctx.doc.data.startZones or {}
                    ctx.doc.data.startZones[effect.zone] = { entryName = ctx.entryName, at = dmhub.serverTime }
                    local zones = rawget(_G, "EncounterZones")
                    if zones ~= nil then
                        zones.BankReveal(ctx.doc, effect.zone, ctx.entryName)
                    end
                end
                applied[#applied + 1] = EncounterScript.DescribeStartZone(effect.zone)
            elseif effect.kind == "revealobject" then
                --banked; the encounter beat switches the inactive object(s)
                --of that name on (EncounterZones.ApplyPendingReveals).
                if ctx.doc ~= nil then
                    ctx.doc.data.revealObjects = ctx.doc.data.revealObjects or {}
                    ctx.doc.data.revealObjects[string.lower(effect.object)] = { name = effect.object, entryName = ctx.entryName, at = dmhub.serverTime }
                end
                applied[#applied + 1] = EncounterScript.DescribeRevealObject(effect.object)
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
    --an item used in the montage never carries a one-location effect into
    --the fight (the montage's own sweep normally got there first).
    pcall(EncounterMontage.EndMontageUses)

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

    if age >= STAGE_DISMISS_SECONDS + STAGE_DISMISS_TIMEOUT then
        printf("EotW: the script stage would not come down after %.1fs; carrying on without it", age)
        EncounterMontage.ClearDismiss()
        return true
    end

    --it has played: take the surface down. The stamp stays until the stage is
    --really gone (Hide would clear it, and a cleared stamp would just be
    --re-stamped next tick -- an endless dissolve if the hide never took).
    pcall(function() GameHud.HidePresentedDialog() end)

    --Never report "gone" on the tick that wrote the clear: the caller then
    --presents the Draw Steel banner, and a clear and a present of the same
    --presentdialog key in one frame upload as the clear. The banner was torn
    --down before it could start combat. The next tick sees the stage gone.
    return false
end

--- host tick ----------------------------------------------------------------

--The tier table to hand the roll dialog: each tier's teaser where it has
--one, its full text otherwise (EncounterScript.TierDisplayText). Only tiers
--1-3: the critical is kept secret until one is rolled, and the stage
--reveals it then.
function EncounterMontage.TeaserTiers(roll)
    local tiers = {}
    for t in ipairs(roll.tiers) do
        if t <= 3 then
            tiers[t] = EncounterScript.TierDisplayText(roll, t, false)
        end
    end
    return tiers
end

--A natural 19-20 is the critical tier (4), whatever the modifiers say.
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
                    entry = entry,
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

--What the montage's last turn did, for the card that follows it (the "over"
--card or the first consequence), in m.lastApplied's shape. Without it the
--last turn's rewards were applied in the same tick the montage ended and
--never shown (2026-10-18 playtest). nil when there is nothing to say.
local function LastTurnResult(m)
    local last = (m.log or {})[#(m.log or {})]
    if last == nil or last.consequence or last.passed then
        return nil
    end
    local lines = {}
    for _, line in ipairs(last.applied or {}) do
        lines[#lines + 1] = line
    end
    if #lines == 0 and type(last.tierText) == "string" and last.tierText ~= "" then
        lines[1] = last.tierText
    end
    if #lines == 0 then
        return nil
    end
    return { entryId = last.entryId, entryName = last.entryName or "", applied = lines }
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
--Does the hero at the turn's entry speak `language` right now? The stage
--asks it again while a garbled line is up, so an item that grants the
--language translates the line in place.
function EncounterMontage.HeroSpeaks(t, language)
    if t == nil or language == nil then
        return false
    end
    local ok, req = pcall(EncounterScript.ParseRequirement, "you speak " .. language)
    return ok and req ~= nil and (HeroRequirementMet(t.heroid, req)) == true
end

local function SceneEnv(t, option, tier, actors)
    local facts = EncounterMontage.HeroFacts(t.heroid)
    local function Met(text)
        local ok, met = pcall(function()
            return EncounterScript.RequirementMet(EncounterScript.ParseRequirement(text), facts)
        end)
        return ok and met == true
    end
    local function HeroSpeaks(language)
        return EncounterMontage.HeroSpeaks(t, language)
    end
    return {
        tier = tier,
        actors = actors or {},
        speaks = HeroSpeaks,
        test = function(atom)
            if atom.op == "speaks" then
                return HeroSpeaks(atom.name)
            elseif atom.op == "is" then
                --"PC is small" / "PC is immune to fire" first, then "PC is
                --a Dwarf" (the article is optional in a scene condition).
                return Met("you are " .. atom.name) or Met("you are a " .. atom.name)
            elseif atom.op == "skilled" then
                return Met("you are skilled in " .. atom.name)
            elseif atom.op == "has" then
                --anything the hero has by name: a skill, perk, ability ...
                return Met("you have " .. atom.name)
            elseif atom.op == "req" then
                return Met(atom.text)
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
                --the words as written ride along, so the stage can translate
                --the line if the hero learns the language mid-scene (an
                --item such as Imp's Tongue).
                step.plain = step.text
                step.text = EncounterScript.Garble(step.text, step.lang)
                step.garbled = true
            end
        end
    end
    m.seq = (m.seq or 0) + 1
    t.scene = { id = m.seq, part = part, steps = steps, cast = cast }
    return #steps
end

--- dice the players roll ---------------------------------------------------------------
--"Roll on Flotsam" and "each party member loses 1d3 recoveries" are rolled on
--the screen by the players (user direction 2026-10-17), the way a delve's
--chest is, not quietly on the host. Before a landed tier or a consequence
--applies, PendingDice lists the rolls its clauses need; the turn (or the
--consequence) waits in m.dice while each hero's player rolls, then the
--effects apply with those totals.

--The player who rolls for a hero: its owner, or `fallback` for a hero the
--whole party shares.
local function RollerFor(heroEntry, fallback)
    local owner = heroEntry ~= nil and heroEntry.ownerId or nil
    if owner == nil or owner == "" or owner == "PARTY" then
        return fallback
    end
    return owner
end

--The dice `effects` need, in the order ApplyEffects uses them: key
--"t:<clause>:<n>" for the nth roll on a table, "r:<clause>:<charid>" for a
--hero's share of a dice recovery loss. ctx is ApplyEffects' context. Hidden
--"{...}" clauses still roll quietly on the host: dice on the screen would
--give them away.
function EncounterMontage.PendingDice(effects, ctx)
    local rolls = {}
    for effectIndex, effect in ipairs(effects or {}) do
        if not effect.hidden then
            if effect.kind == "rolltable" then
                local tableRoll = ctx.entry ~= nil and (ctx.entry.tables or {})[effect.key] or nil
                local hero = ctx.heroEntry
                if tableRoll ~= nil and hero ~= nil then
                    for n = 1, effect.qty do
                        rolls[#rolls + 1] = {
                            key = string.format("t:%d:%d", effectIndex, n),
                            kind = "table",
                            tableKey = effect.key,
                            dice = tableRoll.dice,
                            label = tableRoll.name,
                            heroid = hero.charid,
                            heroName = hero.name,
                            userid = ctx.userid or RollerFor(hero, dmhub.loginUserid),
                        }
                    end
                end
            elseif effect.kind == "loserecovery" and effect.dice ~= nil then
                local targets = {}
                if effect.target == "party" then
                    targets = EncounterMontage.Heroes()
                elseif ctx.heroEntry ~= nil then
                    targets = { ctx.heroEntry }
                end
                for _, hero in ipairs(targets) do
                    rolls[#rolls + 1] = {
                        key = string.format("r:%d:%s", effectIndex, hero.charid),
                        kind = "recovery",
                        dice = effect.dice,
                        label = "Recoveries lost",
                        heroid = hero.charid,
                        heroName = hero.name,
                        userid = RollerFor(hero, ctx.userid or dmhub.loginUserid),
                    }
                end
            end
        end
    end
    return rolls
end

--The lowest and highest a plain dice expression ("1d3", "2d6") can roll.
local function DiceRange(dice)
    local count, sides = string.match(string.lower(dice or ""), "^(%d*)d(%d+)$")
    local n = math.max(1, tonumber(count) or 1)
    return n, n * math.max(1, tonumber(sides) or 1)
end

--Put dice out for the players: d = { purpose, entryName, entryId, rolls, ... }.
local function OpenDice(m, d)
    m.seq = (m.seq or 0) + 1
    d.seq = m.seq
    d.openedAt = dmhub.serverTime
    m.dice = d
    printf("EotW montage: %s waits on %d dice", tostring(d.entryName), #d.rolls)
end

--Apply the consequence the montage is on (m.consequenceIndex) and step on.
--`totals` are the dice its players rolled; nil the first time, when any dice
--it needs are put out instead (the consequence then waits in m.dice).
local function ApplyConsequence(m, doc, beat, userid, totals)
    local idx = m.consequenceIndex or 1
    local entryId = (m.consequences or {})[idx]
    if entryId == nil then
        m.phase = "done"
        return "montage done"
    end
    local entry = EncounterScript.FindEntry(beat, entryId)
    local applied = {}
    if entry ~= nil and entry.consequence ~= nil then
        local ctx = {
            heroEntry = nil,
            userid = userid,
            entryName = entry.name,
            entryId = entry.id,
            entry = entry,
            montage = m,
            doc = doc,
        }
        if totals == nil then
            local rolls = EncounterMontage.PendingDice(entry.consequence.effects, ctx)
            if #rolls > 0 then
                OpenDice(m, { purpose = "consequence", entryName = entry.name, entryId = entry.id,
                    consequenceIndex = idx, userid = userid, rolls = rolls })
                return string.format("consequence of %s waits on the dice", entryId)
            end
        end
        ctx.diceTotals = totals
        applied = EncounterMontage.ApplyEffects(entry.consequence.effects, ctx)
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
end

--Apply the landed tier of a turn's chosen option and close the turn out:
--effects, allies, the acted/taken bookkeeping, and the log line. An option
--with outcome lines plays them first (ResolveTurn); this runs once they
--have been read.
local DelveObstacleResolved

local function ApplyResolution(m, doc, t, entry, option, tierIndex, heroes, userid)
    --inside a delve an obstacle's result is applied and the delve goes on;
    --the turn only ends when the hero leaves.
    if t.delve ~= nil and t.delve.obstacleId ~= nil then
        DelveObstacleResolved(m, doc, t, entry, option, tierIndex, heroes, userid)
        return
    end
    local hero = HeroByCharid(heroes, t.heroid)
    local effects = EncounterMontage.VersionEffects(option, tierIndex)
    local ctx = {
        heroEntry = hero,
        userid = userid,
        entryName = entry.name,
        entryId = entry.id,
        entry = entry,
        montage = m,
        doc = doc,
    }
    --dice the tier needs go out to the players first; this runs again with
    --their totals once every roll is in (ResumeDice).
    if t.diceTotals == nil then
        local rolls = EncounterMontage.PendingDice(effects, ctx)
        if #rolls > 0 then
            OpenDice(m, { purpose = "turn", entryName = entry.name, entryId = entry.id,
                tier = tierIndex, userid = userid, rolls = rolls })
            t.status = "dice"
            return
        end
    end
    ctx.diceTotals = t.diceTotals
    t.diceTotals = nil
    local applied, newAllies = EncounterMontage.ApplyEffects(effects, ctx)
    if #newAllies > 0 then
        doc.data.allies = doc.data.allies or {}
        doc.data.allies[t.heroid] = doc.data.allies[t.heroid] or {}
        for _, charid in ipairs(newAllies) do
            table.insert(doc.data.allies[t.heroid], charid)
        end
    end
    for i = #(t.perkLines or {}), 1, -1 do
        table.insert(applied, 1, t.perkLines[i])
    end
    t.status = "resolved"
    t.tier = tierIndex
    if option.roll ~= nil and tierIndex ~= nil and tierIndex > 0 then
        t.tierText = EncounterScript.VisibleText(option.roll.tiers[tierIndex])
    else
        t.tierText = EncounterScript.VisibleText((option.free or {}).text or "")
    end
    t.applied = applied
    t.resolvedAt = dmhub.serverTime
    m.acted = m.acted or {}
    m.acted[t.heroid] = true
    if entry.kind == "opportunity" then
        m.taken = m.taken or {}
        m.taken[entry.id] = true
    end
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
        --the landed tier's own words, for the hero slot's hover on the stage.
        tierText = t.tierText,
        applied = applied,
        knack = t.knackReason,
    }
end

--Every die is in (or the wait ran out): the turn or the consequence that
--was waiting applies with the totals the players rolled.
local function ResumeDice(m, doc, beat, heroes)
    local d = m.dice
    m.dice = nil
    if d == nil then
        return
    end
    local totals = {}
    for _, r in ipairs(d.rolls or {}) do
        totals[r.key] = r.total
    end
    if d.purpose == "consequence" then
        if m.phase == "consequences" and (m.consequenceIndex or 1) == d.consequenceIndex then
            ApplyConsequence(m, doc, beat, d.userid, totals)
        end
        return
    end
    local t = m.turn
    if t == nil or t.status ~= "dice" then
        return
    end
    local entry = EncounterMontage.TurnEntry(beat, t)
    local option = EncounterMontage.TurnOption(entry, t)
    if entry == nil or option == nil then
        t.status = "choosing"
        return
    end
    t.diceTotals = totals
    ApplyResolution(m, doc, t, entry, option, d.tier, heroes, d.userid)
end

--A test has landed on its final tier (after any perk): play the option's
--outcome lines, if it has any for this tier, before anything is applied --
--the witch hands over the potions, THEN they arrive in the haul.
local function ResolveTurn(m, doc, t, entry, option, tierIndex, heroes, userid)
    --a free option (tier 0) has no tier for its outcome lines to test.
    local sceneTier = nil
    if tierIndex ~= nil and tierIndex > 0 then
        sceneTier = tierIndex
    end
    if option.postScene ~= nil and BuildScenePart(m, t, entry, option, "outcome", sceneTier) > 0 then
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
--
--An in-order delve ("Order: in sequence", user direction 2026-10-04) is a
--story chain instead, e.g. a rescue: its obstacles come in the order
--written, after each one the hero may press on (free) or turn back, chests
--are optional, and finishing the last step plays its "## End" scene.

local function HeroRecoveries(heroid)
    local n = 0
    local tok = dmhub.GetCharacterById(heroid)
    if tok ~= nil and tok.valid and tok.properties ~= nil then
        pcall(function() n = tok.properties:RecoveriesAvailableToSpend() or 0 end)
    end
    return n
end

EncounterMontage.HeroRecoveries = HeroRecoveries

--Pressing deeper after a chest costs a Recovery on the spot (user direction
--2026-09-24). It is only offered with Recoveries to spare after paying:
--a hero left on 0 would be forced out before meeting anything.
EncounterMontage.DELVE_PRESS_ON_COST = 1

--What pressing on costs in this delve: nothing in an in-order delve ("Order:
--in sequence", a story chain like a rescue), whose steps carry their own costs.
function EncounterMontage.DelvePressOnCost(delve)
    if delve ~= nil and delve.ordered then
        return 0
    end
    return EncounterMontage.DELVE_PRESS_ON_COST
end

function EncounterMontage.CanPressDeeper(heroid, delve)
    local cost = EncounterMontage.DelvePressOnCost(delve)
    return cost == 0 or HeroRecoveries(heroid) > cost
end

--Chest rows the party has never landed on read "???" (user direction
--2026-09-24); once landed, a row stays known for every later chest.
local function ChestRowKey(row)
    return string.format("%d-%d", row.lo or 0, row.hi or 0)
end

function EncounterMontage.ChestRowSeen(delveName, row)
    local seen = nil
    pcall(function() seen = mod:GetDocumentSnapshot(DOC_ID).data.chestSeen end)
    local forDelve = seen ~= nil and seen[EncounterScript.MatchKey(delveName or "")] or nil
    return forDelve ~= nil and forDelve[ChestRowKey(row)] == true
end

local function MarkChestRowSeen(doc, delveName, row)
    local key = EncounterScript.MatchKey(delveName or "")
    doc.data.chestSeen = doc.data.chestSeen or {}
    doc.data.chestSeen[key] = doc.data.chestSeen[key] or {}
    doc.data.chestSeen[key][ChestRowKey(row)] = true
end

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
    t.pardon = nil
    t.pardoned = nil
    t.chest = nil
    t.knackIndex = nil
    t.knackReason = nil
    t.offers = nil
    t.offerOpenedAt = nil
    t.perkLines = nil
    t.blessing = nil
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

--Walk out: voluntarily ("leave"), with no Recoveries left ("forced"),
--because every obstacle has been met ("exhausted"), or at the end of an
--in-order delve ("complete": its "## End" scene, if it has one).
local function DelveLeave(m, doc, t, heroes, why)
    t.delve.obstacleId = nil
    ClearTest(t)
    local lead = nil
    local delve = EncounterMontage.TurnDelve(t)
    if why == "complete" then
        DelveScene(m, doc, t, heroes, "finish", "delve-end", nil)
        return
    end
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
        DelveLeave(m, doc, t, heroes, cond(delve.ordered, "complete", "exhausted"))
        return
    end
    --an in-order delve meets its obstacles as written; otherwise at random.
    local ob = cond(delve.ordered, pool[1], pool[math.random(1, #pool)])
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
    local delve = EncounterMontage.TurnDelve(t)
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
        --an in-order delve logs its steps: "2 of 3 steps".
        ordered = delve ~= nil and delve.ordered == true or nil,
        steps = delve ~= nil and #(delve.obstacles or {}) or nil,
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
    DelveAddApplied(t, t.perkLines)
    local applied, newAllies = EncounterMontage.ApplyEffects(EncounterMontage.VersionEffects(option, tierIndex), {
        heroEntry = hero,
        userid = userid,
        entryName = t.delve.entryName,
        entryId = t.entryId,
        entry = entry,
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
    local delve = EncounterMontage.TurnDelve(t)
    --an in-order delve whose last step is done has reached its end, even
    --if that step left the hero with no Recoveries.
    local remaining = 0
    for _, ob in ipairs((delve and delve.obstacles) or {}) do
        if not (t.delve.used or {})[ob.id] then
            remaining = remaining + 1
        end
    end
    if delve ~= nil and delve.ordered and remaining == 0 then
        DelveLeave(m, doc, t, heroes, "complete")
        return
    end
    if HeroRecoveries(t.heroid) <= 0 then
        DelveLeave(m, doc, t, heroes, "forced")
        return
    end
    if delve ~= nil and delve.sections.chest ~= nil and delve.sections.chest.table ~= nil
        and t.delve.sinceChest >= (t.delve.chestAt or 1) then
        t.delve.sinceChest = 0
        t.delve.chestAt = ChestInterval(delve)
        DelveScene(m, doc, t, heroes, "chest", "delve-chest")
        return
    end
    --an in-order delve offers the way back after every step.
    if delve ~= nil and delve.ordered then
        DelveScene(m, doc, t, heroes, "continue", "delve-choice")
        return
    end
    DelveNextObstacle(m, doc, t, heroes)
end

--- perks (host side) ------------------------------------------------------------
--
--The real rules of the perks (and the one class feature) that are about
--tests, played out in the montage rather than left to the author:
--  Brawny / Lucky Dog: a failed Might / intrigue test can be raised a tier
--    for 1d6 + level Stamina (offered to the roller right after the roll).
--  Put Your Back Into It!: once per montage, raise an ally's tier 1 to
--    tier 2 (offered to the perk's owner when an ally fails).
--  Pardon My Friend: when the hero fails a Presence test, another hero with
--    the perk may make it instead, with a bane; their roll replaces the
--    hero's. Once per test.
--  Team Leader: before anyone acts, spend a hero token so every hero tests
--    as if they had the leader's exploration skills for the montage.
--  Ritualist: once a round, bless your own test: a double edge on it
--    (EncounterMontage.AppendPerkModifiers).
--  Born Tracker (edge), Polymath / Handy (+1 with no skill that applies),
--    Power Player (Might for Brag / Flirt / Intimidate): roll chips.
--  Mighty Leaps (Fury): a Might test to jump never lands below tier 2.
--Perks are read off the hero's facts by name (TestRiders.CreatureFacts).

local PERK_OFFER_SECONDS = 30
EncounterMontage.PERK_OFFER_SECONDS = PERK_OFFER_SECONDS

function EncounterMontage.HeroHasPerk(charid, perkName)
    local facts = EncounterMontage.HeroFacts(charid)
    return (facts.perk or {})[TestRiders.NormalizeName(perkName)] == true
end

function EncounterMontage.HeroHasTrait(charid, name)
    local facts = EncounterMontage.HeroFacts(charid)
    local n = TestRiders.NormalizeName(name)
    return (facts.trait or {})[n] == true or (facts.ability or {})[n] == true
end

--The skill rows of a list of skill ids.
local function SkillInfos(skillids)
    local result = {}
    local t = dmhub.GetTable(Skill.tableName) or {}
    for _, id in ipairs(skillids or {}) do
        if t[id] ~= nil then
            result[#result + 1] = t[id]
        end
    end
    return result
end

local function SkillsInclude(skillids, names)
    for _, info in ipairs(SkillInfos(skillids)) do
        if names[string.lower(info.name or "")] then
            return true
        end
    end
    return false
end

local function SkillsInCategory(skillids, category)
    for _, info in ipairs(SkillInfos(skillids)) do
        local cat = nil
        pcall(function() cat = info.category end)
        if string.lower(cat or "") == category then
            return true
        end
    end
    return false
end

--The attribute id of a characteristic by name ("might").
local function AttrIdNamed(name)
    for id, info in pairs(creature.attributesInfo or {}) do
        if string.lower(info.description or "") == name then
            return id
        end
    end
    return nil
end

local function IsMightAttr(attrid)
    return attrid ~= nil and attrid == AttrIdNamed("might")
end

local function IsPresenceAttr(attrid)
    return attrid ~= nil and attrid == AttrIdNamed("presence")
end

local function PerkUsed(m, key)
    return (m.perkUsed or {})[key] == true
end

local function MarkPerkUsed(m, key)
    m.perkUsed = m.perkUsed or {}
    m.perkUsed[key] = true
    m.perkSeq = (m.perkSeq or 0) + 1
end

--Team Leader: does the party's leader lend this skill to everyone?
function EncounterMontage.TeamLeaderGrants(skillid, m)
    m = m or EncounterMontage.GetState()
    local leader = m ~= nil and m.teamLeader or nil
    if leader == nil or skillid == nil then
        return false
    end
    for _, id in ipairs(leader.skills or {}) do
        if id == skillid then
            return true
        end
    end
    return false
end

--Power Player: Might may stand in for the listed characteristics on a
--Brag, Flirt or Intimidate test. Returns the (possibly widened) set.
function EncounterMontage.PerkCharacteristics(c, charid, characteristics, skills)
    if not EncounterMontage.HeroHasPerk(charid, "Power Player") then
        return characteristics
    end
    if not SkillsInclude(skills, { brag = true, flirt = true, intimidate = true }) then
        return characteristics
    end
    local might = AttrIdNamed("might")
    if might == nil then
        return characteristics
    end
    local widened = {}
    for k, v in pairs(characteristics or {}) do
        widened[k] = v
    end
    widened[might] = true
    return widened
end

--One synthetic, pre-ticked roll-dialog chip (like a rider's).
local function PerkChip(name, description, modtype, replaceText)
    local chip = nil
    pcall(function()
        --replaceText ("1") is what an "appendroll" chip adds to the roll; the
        --power init leaves it alone.
        local m = CharacterModifier.new{
            guid = dmhub.GenerateGuid(),
            name = name,
            description = description,
            behavior = "power",
            domains = {},
            replaceText = replaceText,
        }
        CharacterModifier.TypeInfo.power.init(m)
        m.rollType = "test_power_roll"
        m.modtype = modtype
        m.activationCondition = true
        chip = { modifier = m, context = {}, hint = { result = true, justification = { description } } }
    end)
    return chip
end

--The perk chips for the acting hero's test (Born Tracker, Polymath, Handy,
--a Ritualist's blessing). Appends to `modifiers`.
function EncounterMontage.AppendPerkModifiers(modifiers, c, charid, turn, option, skills, attrid)
    local function Add(chip)
        if chip ~= nil then
            modifiers[#modifiers + 1] = chip
        end
    end
    if EncounterMontage.HeroHasPerk(charid, "Born Tracker") and SkillsInclude(skills, { track = true, navigate = true }) then
        Add(PerkChip("Edge: Born Tracker", "Born Tracker: an edge on tests to track creatures or find your way.", "edge"))
    end
    local skilled = false
    for _, info in ipairs(SkillInfos(skills)) do
        local ok = false
        pcall(function() ok = c:ProficientInSkill(info) end)
        if ok or EncounterMontage.TeamLeaderGrants(info.id) then
            skilled = true
        end
    end
    if not skilled then
        if EncounterMontage.HeroHasPerk(charid, "Polymath") and SkillsInCategory(skills, "lore") then
            Add(PerkChip("+1: Polymath", "Polymath: +1 on a test to recall lore when no skill you have applies.", "appendroll", "1"))
        end
        if EncounterMontage.HeroHasPerk(charid, "Handy") and SkillsInCategory(skills, "crafting") then
            Add(PerkChip("+1: Handy", "Handy: +1 on a test to craft when no skill you have applies.", "appendroll", "1"))
        end
    end
    if turn ~= nil and turn.blessing ~= nil then
        local who = turn.blessing.heroName or "a Ritualist"
        Add(PerkChip(string.format("Double Edge: blessed by %s", who),
            string.format("Ritualist: %s blessed this test.", who), "double_edge"))
    end
    return modifiers
end

--Mighty Leaps (Fury): a Might test to jump never lands below tier 2.
local function ApplyTierFloors(t, option, tierIndex)
    if tierIndex < 2 and IsMightAttr(t.attrid) and SkillsInclude(EncounterMontage.OptionSkills(option), { jump = true })
        and EncounterMontage.HeroHasTrait(t.heroid, "Mighty Leaps") then
        t.perkLines = t.perkLines or {}
        t.perkLines[#t.perkLines + 1] = "Mighty Leaps: a Might jump never lands below tier 2"
        return 2
    end
    return tierIndex
end

--The lowest total that lands on a tier (Draw Steel: 12 and 17), so the
--total shown with a tier a perk paid for agrees with it.
local TIER_FLOOR_TOTAL = { [2] = 12, [3] = 17 }

local function RaiseTier(t, by)
    t.tier = math.min(3, (t.tier or 1) + (by or 1))
    t.baseTier = t.tier
    local floor = TIER_FLOOR_TOTAL[t.tier]
    if floor ~= nil and tonumber(t.baseTotal) ~= nil and tonumber(t.baseTotal) < floor then
        t.baseTotal = floor
        t.total = floor
    end
end

--The perks that could rescue a failed (tier 1) test, as offers:
--{ kind, heroid, heroName, perk, text }.
local function PerkOffersFor(m, t, option, heroes)
    local offers = {}
    if (t.tier or 1) ~= 1 then
        return offers
    end
    local skills = EncounterMontage.OptionSkills(option)
    if IsMightAttr(t.attrid) and EncounterMontage.HeroHasPerk(t.heroid, "Brawny") then
        offers[#offers + 1] = { kind = "stamina", heroid = t.heroid, heroName = t.heroName, perk = "Brawny",
            text = "Lose 1d6 + your level Stamina to raise this failed Might test by one tier." }
    end
    if SkillsInCategory(skills, "intrigue") and EncounterMontage.HeroHasPerk(t.heroid, "Lucky Dog") then
        offers[#offers + 1] = { kind = "stamina", heroid = t.heroid, heroName = t.heroName, perk = "Lucky Dog",
            text = "Lose 1d6 + your level Stamina to raise this failed intrigue test by one tier." }
    end
    --Pardon My Friend: another hero makes the failed Presence test instead.
    if IsPresenceAttr(t.attrid) and not t.pardoned then
        for _, hero in ipairs(heroes or {}) do
            if hero.charid ~= t.heroid and EncounterMontage.HeroHasPerk(hero.charid, "Pardon My Friend") then
                offers[#offers + 1] = { kind = "pardon", heroid = hero.charid, heroName = hero.name, perk = "Pardon My Friend",
                    text = string.format("Step in: make this Presence test yourself with a bane. Your roll replaces %s's.", t.heroName or "the hero") }
            end
        end
    end
    for _, hero in ipairs(heroes or {}) do
        if hero.charid ~= t.heroid and not PerkUsed(m, "backintoit:" .. hero.charid)
            and EncounterMontage.HeroHasPerk(hero.charid, "Put Your Back Into It!") then
            offers[#offers + 1] = { kind = "backintoit", heroid = hero.charid, heroName = hero.name, perk = "Put Your Back Into It!",
                text = string.format("Once this montage: turn %s's tier 1 into tier 2.", t.heroName or "the hero") }
        end
    end
    return offers
end

--A test has landed (after any perk offers): resolve it.
local function AfterTestLanded(m, doc, t, beat, entry, option, heroes, userid)
    t.offers = nil
    t.offerOpenedAt = nil
    ResolveTurn(m, doc, t, entry, option, t.tier or 1, heroes, userid)
    return string.format("%s rolled tier %d on %s", t.heroName, t.tier or 1, entry.name)
end

--The dice come out for the hero making the test.
local function StartRoll(m, t)
    m.seq = (m.seq or 0) + 1
    t.rollSeq = m.seq
    t.status = "rolling"
end


--Use one perk offer: pay its cost and raise the test a tier.
local function UsePerkOffer(m, doc, t, offer, heroes)
    local hero = HeroByCharid(heroes, offer.heroid)
    if offer.kind == "stamina" then
        local level = tonumber(EncounterMontage.HeroFacts(offer.heroid).stat.level) or 1
        local loss = math.random(1, 6) + level
        if hero ~= nil and hero.token ~= nil then
            LoseStamina(hero.token, loss, offer.perk)
        end
        t.perkLines = t.perkLines or {}
        t.perkLines[#t.perkLines + 1] = string.format("%s: lost %d Stamina to raise the test a tier", offer.perk, loss)
    elseif offer.kind == "backintoit" then
        MarkPerkUsed(m, "backintoit:" .. offer.heroid)
        t.perkLines = t.perkLines or {}
        t.perkLines[#t.perkLines + 1] = string.format("%s put their back into it: tier 1 became tier 2", offer.heroName or "A hero")
    end
    RaiseTier(t, 1)
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
        StartRoll(m, t)
    elseif after == "free" then
        --a free option's own lines have played: no dice, straight to its
        --outcome (lines, then effects).
        local option = EncounterMontage.TurnOption(entry, t)
        if option == nil or option.free == nil then
            t.status = "choosing"
            return
        end
        ResolveTurn(m, doc, t, entry, option, 0, heroes, t.userid)
    elseif after == "resolve" then
        local option = EncounterMontage.TurnOption(entry, t)
        if option == nil or (option.roll == nil and option.free == nil) then
            t.status = "choosing"
            return
        end
        local tier = t.pendingTier
        if tier == nil then
            tier = t.tier or 1
        end
        ApplyResolution(m, doc, t, entry, option, tier, heroes, t.resolveUserid or t.userid)
    else
        t.status = "choosing"
    end
end

--- consumables in the montage -------------------------------------------------------
--Heroes may use their consumables during a montage (user direction
--2026-10-09). The hero's own player clicks an item beside the hero's card
--and picks a use; THEIR client casts the item's ability just as the action
--bar would (same behaviors, the item spent), at no action cost, any time in
--the rounds except while that hero's own roll is out.
--
--How long what it leaves behind lasts:
--  * a SHORT effect (rounds, end of turn, save ends, end of encounter) lasts
--    one montage location: the turn the hero is in when they use it, or
--    else the next turn they take. It
--    ends when that turn resolves; anything left ends with the montage.
--  * a LONG effect (until a respite, or with no end) lasts the whole
--    encounter, combat included.
--A short duration cannot simply be kept: an effect counted in rounds that
--is made outside combat expires at once (CharacterOngoingEffectInstance:
--Expired). So while a montage use is casting, short effects are applied
--with no duration and marked on the instance itself:
--  instance.eotwMontageUse = { itemid, item, turnSeq }
--     -- turnSeq: the turn it lasts through, nil until the hero joins one.
--The host's tick (MaintainMontageUses) binds, ends and sweeps them. The
--marker lives on the token, not in a request, because a player's requests
--share one slot and a quick second click would overwrite the first.
--
--  data.montage.consumeSeq = n -- bumped by every use ("consumed"), so the
--                                 stage rebuilds what it shows: a language
--                                 from an item can reveal an option.

local Consume = {}

--What a montage use can carry out away from the map: effects on the hero,
--healing, purging, temporary Stamina, Recoveries. Anything else (strikes,
--areas, walls, forced movement, raising the dead) needs the battle map.
Consume.SAFE_BEHAVIORS = {
    ActivatedAbilityApplyOngoingEffectBehavior = true,
    ActivatedAbilityHealBehavior = true,
    ActivatedAbilityPurgeEffectsBehavior = true,
    ActivatedAbilityGrantTemporaryStaminaBehavior = true,
    ActivatedAbilityReplenishBehavior = true,
}

Consume.NEEDS_MAP = "Needs the battle map: use it in combat."

--Durations that outlast a single location: until a respite, or none at all.
function Consume.IsShort(duration)
    return not (duration == nil or duration == "until_rest" or duration == "until_long_rest")
end

--The behaviors of `ability` that run for `mode` (nil = an ability without
--modes).
function Consume.BehaviorsForMode(ability, mode)
    local result = {}
    for _, b in ipairs(ability:try_get("behaviors", {})) do
        local modes = b:try_get("modesSelected")
        if mode == nil or modes == nil or #modes == 0 or table.contains(modes, mode) then
            result[#result + 1] = b
        end
    end
    return result
end

--Can a montage use carry this behavior out? An "invoke ability" counts when
--it only runs a self-targeted ability made of safe behaviors (Giant's-Blood
--Flame's Coat Weapon).
function Consume.SafeBehavior(b, depth)
    local typeName = b.typeName
    if Consume.SAFE_BEHAVIORS[typeName] then
        return true
    end
    if typeName == "ActivatedAbilityInvokeAbilityBehavior" and (depth or 0) < 2 then
        local custom = b:try_get("customAbility")
        if custom ~= nil and b:try_get("targeting", "self") == "self" and custom:try_get("targetType", "self") == "self" then
            for _, inner in ipairs(custom:try_get("behaviors", {})) do
                if not Consume.SafeBehavior(inner, (depth or 0) + 1) then
                    return false
                end
            end
            return true
        end
    end
    return false
end

--The ongoing effects these behaviors would put on creature `c` using the
--item on themselves: { { effectid, duration }, ... }. A behavior's target
--filter is weighed with `c` as both caster and target, as a self-cast
--would (Growth Potion: "target = caster"; Elixir: "Victories = 3").
function Consume.EffectsOf(behaviors, c, depth, out)
    out = out or {}
    for _, b in ipairs(behaviors) do
        if b.typeName == "ActivatedAbilityApplyOngoingEffectBehavior" then
            local effectid = b:try_get("ongoingEffect")
            if b:try_get("ongoingEffectSource", "specific") == "specific" and type(effectid) == "string" then
                local pass = true
                local filter = b:try_get("filterTarget", "")
                if type(filter) == "string" and filter ~= "" and c ~= nil then
                    pcall(function()
                        pass = GoblinScriptTrue(ExecuteGoblinScript(filter, c:LookupSymbol({ target = c, caster = c }), 1, "Montage consumable filter"))
                    end)
                end
                if pass then
                    out[#out + 1] = { effectid = effectid, duration = b:try_get("duration") }
                end
            end
        elseif b.typeName == "ActivatedAbilityInvokeAbilityBehavior" and (depth or 0) < 2 then
            local custom = b:try_get("customAbility")
            if custom ~= nil then
                Consume.EffectsOf(custom:try_get("behaviors", {}), c, (depth or 0) + 1, out)
            end
        end
    end
    return out
end

--Every way a hero could use one of their items in the montage: the item's
--ability, or each of its modes.
--  { { mode, label, rules, usable, reason, shortReason,
--      lasts = "location"|"encounter"|nil, targets = "self"|"group" }, ... }
--`shortReason` is the few words a greyed menu entry carries ("combat only").
--`lasts` says how long its effects stay: one location if any is short, the
--whole encounter if all are long, nil when it leaves no effect (a heal).
--"group" targets ("you and each ally within 5 squares") reach only the
--user: a hero is alone at a montage location.
function EncounterMontage.ConsumableUses(charid, itemid)
    local gear = dmhub.GetTable("tbl_Gear") or {}
    local item = gear[itemid]
    if item == nil or not EquipmentCategory.IsConsumable(item) then
        return {}
    end
    local ability = item:try_get("consumable")
    if type(ability) ~= "table" then
        return { { label = "Use", usable = false, reason = "This item has nothing to use." } }
    end
    local tok = dmhub.GetCharacterById(charid)
    local c = tok ~= nil and tok.valid and tok.properties or nil

    local targetType = ability:try_get("targetType", "self")
    local targets = nil
    if targetType == "self" then
        targets = "self"
    elseif targetType == "target" and ability:try_get("selfTarget", false) then
        targets = "self"
    elseif targetType == "all" and ability:try_get("selfTarget", false) and ability:try_get("targetAllegiance", "") == "ally" then
        targets = "group"
    end

    local filterReason = nil
    if c ~= nil then
        pcall(function() filterReason = ability:AbilityFilterFailureMessage(c) end)
    end

    --false stands for "no mode": an ability without modes is one use.
    ---@type (integer|false)[]
    local modes = { false }
    local modeList = ability:try_get("modeList", {})
    if ability:try_get("multipleModes", false) and #modeList > 0 then
        modes = {}
        for i = 1, #modeList do
            modes[i] = i
        end
    end

    local result = {}
    for _, mode in ipairs(modes) do
        local modeIndex = mode ~= false and mode or nil
        local behaviors = Consume.BehaviorsForMode(ability, modeIndex)
        local usable, reason, shortReason = true, nil, nil
        if #behaviors == 0 then
            usable, reason, shortReason = false, "Used in combat, not in a montage.", "combat only"
        elseif targets == nil then
            usable, reason, shortReason = false, Consume.NEEDS_MAP, "combat only"
        else
            for _, b in ipairs(behaviors) do
                if not Consume.SafeBehavior(b, 0) then
                    usable, reason, shortReason = false, Consume.NEEDS_MAP, "combat only"
                    break
                end
            end
        end
        if usable and filterReason ~= nil then
            usable, reason, shortReason = false, filterReason, filterReason
        end
        local lasts = nil
        if usable then
            for _, e in ipairs(Consume.EffectsOf(behaviors, c, 0)) do
                if Consume.IsShort(e.duration) then
                    lasts = "location"
                elseif lasts == nil then
                    lasts = "encounter"
                end
            end
        end
        local entry = modeIndex ~= nil and modeList[modeIndex] or nil
        result[#result + 1] = {
            mode = modeIndex,
            label = entry ~= nil and entry.text or "Use",
            rules = entry ~= nil and entry.rules or nil,
            usable = usable,
            reason = reason,
            shortReason = shortReason,
            lasts = lasts,
            targets = targets,
        }
    end
    return result
end

--Why this hero cannot use an item right now, or nil when they can.
function EncounterMontage.ConsumeBlockedReason(charid)
    local m = EncounterMontage.GetState()
    if m == nil or m.phase ~= "rounds" then
        return "Items can be used while the montage rounds are under way."
    end
    local t = m.turn
    if t ~= nil then
        if t.status == "rolling" and t.heroid == charid then
            return "Not while this hero's test is being rolled."
        end
        if t.status == "pardon" and t.pardon ~= nil and t.pardon.heroid == charid then
            return "Not while this hero is rolling for Pardon My Friend."
        end
    end
    if Consume.capture ~= nil then
        return "Another item is being used."
    end
    return nil
end

--Is this hero the one at the entry in the turn in flight?
function Consume.InLiveTurn(t, charid)
    return t ~= nil and t.status ~= "resolved" and t.heroid == charid
end

--While a montage use is casting on THIS client: { charids = { [charid] = true },
--itemid, item, turnSeq }. ApplyOngoingEffect (below) reads it.
Consume.capture = nil

--Short effects made during a montage use get no duration and the marker
--the host ends them by (see the section header). Everything else passes
--straight through.
local g_baseApplyOngoingEffect = creature.ApplyOngoingEffect
function creature:ApplyOngoingEffect(ongoingEffectid, duration, casterInfo, options)
    local capture = Consume.capture
    if capture == nil then
        return g_baseApplyOngoingEffect(self, ongoingEffectid, duration, casterInfo, options)
    end
    local charid = dmhub.LookupTokenId(self)
    if charid == nil or not capture.charids[charid] or not Consume.IsShort(duration) then
        return g_baseApplyOngoingEffect(self, ongoingEffectid, duration, casterInfo, options)
    end
    local instance = g_baseApplyOngoingEffect(self, ongoingEffectid, nil, casterInfo, options)
    if instance ~= nil then
        instance.eotwMontageUse = { itemid = capture.itemid, item = capture.item, turnSeq = capture.turnSeq }
    end
    return instance
end

--Send "consumed" once the user's previous request has been handled: a
--player's requests share one slot, so sending over an unhandled one would
--drop it.
function Consume.SendWhenFree(kind, args, waited)
    waited = waited or 0
    local m = EncounterMontage.GetState()
    local userid = dmhub.loginUserid
    local prev = m ~= nil and (m.requests or {})[userid] or nil
    local handled = m ~= nil and tonumber((m.handled or {})[userid]) or 0
    if prev ~= nil and (tonumber(prev.seq) or 0) > (handled or 0) and waited < 10 then
        dmhub.Schedule(0.25, function()
            if mod.unloaded then
                return
            end
            Consume.SendWhenFree(kind, args, waited + 0.25)
        end)
        return
    end
    EncounterMontage.SendRequest(kind, args)
end

--Use one of a hero's items (client side; the local user must control the
--hero). `mode` picks a mode of a multi-mode item. Returns false and a
--reason when it cannot be used now.
function EncounterMontage.ConsumeItem(charid, itemid, mode)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid or tok.properties == nil then
        return false, "No such hero."
    end
    if not LocalControlsHero(charid) then
        return false, "That is not your hero."
    end
    local blocked = EncounterMontage.ConsumeBlockedReason(charid)
    if blocked ~= nil then
        return false, blocked
    end
    if tok.properties:GetItemQuantity(itemid) < 1 then
        return false, "The hero no longer has that item."
    end
    local use = nil
    for _, u in ipairs(EncounterMontage.ConsumableUses(charid, itemid)) do
        if u.mode == mode then
            use = u
        end
    end
    if use == nil or not use.usable then
        return false, use ~= nil and use.reason or "That item cannot be used here."
    end

    local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
    local ability = item:try_get("consumable"):MakeTemporaryClone()
    ability._tmp_boundCaster = tok.properties

    local m = EncounterMontage.GetState()
    local t = m ~= nil and m.turn or nil
    local targets = { { token = tok } }
    local charids = { [charid] = true }

    local capture = {
        charids = charids,
        itemid = itemid,
        item = item.name,
        turnSeq = (t ~= nil and Consume.InLiveTurn(t, charid)) and t.seq or nil,
    }
    Consume.capture = capture
    local finished = false
    local function Finish(_ability, _token, options)
        if finished then
            return
        end
        finished = true
        if Consume.capture == capture then
            Consume.capture = nil
        end
        local aborted = options ~= nil and options.abort == true
        Consume.SendWhenFree("consumed", { heroid = charid, itemid = itemid, item = item.name, mode = mode, aborted = aborted })
    end
    --a cast that never finishes must not leave every later effect marked.
    dmhub.Schedule(60, function()
        if Consume.capture == capture then
            Consume.capture = nil
        end
    end)
    local ok, err = pcall(function()
        ability:Cast(tok, targets, {
            pay = true,
            --the item is all it costs: no maneuver is spent in a montage.
            costOverride = { details = {}, consumables = { [itemid] = 1 } },
            symbols = { mode = mode or 1 },
            OnFinishCastHandlers = { Finish },
        })
    end)
    if not ok then
        if Consume.capture == capture then
            Consume.capture = nil
        end
        printf("EotW montage: using %s failed: %s", tostring(item.name), tostring(err))
        return false, "Something went wrong using that item."
    end
    return true
end

--Host: bind, end and sweep the short effects montage uses left on the
--heroes (see the section header), and keep the haul strip honest about
--consumables that have been used. Called from the host tick inside its
--open document change.
local function MaintainMontageUses(m, doc, heroes)
    local t = m.turn
    for _, hero in ipairs(heroes) do
        local tok = hero.token
        local removeIds, bind = {}, {}
        local any = false
        for _, inst in ipairs(tok.properties:try_get("ongoingEffects", {})) do
            local use = inst:try_get("eotwMontageUse")
            if type(use) == "table" then
                any = true
                if m.phase ~= "rounds" then
                    removeIds[inst.id] = true
                elseif use.turnSeq ~= nil then
                    if t == nil or t.seq ~= use.turnSeq or t.status == "resolved" then
                        removeIds[inst.id] = true
                    end
                elseif Consume.InLiveTurn(t, hero.charid) then
                    bind[inst.id] = true
                end
            end
        end
        if any and (next(removeIds) ~= nil or next(bind) ~= nil) then
            ElevateToHostPermissions()
            local ok, err = pcall(function()
                tok:ModifyProperties{
                    description = "Montage: item effects",
                    undoable = false,
                    execute = function()
                        local list = tok.properties:try_get("ongoingEffects", {})
                        for i = #list, 1, -1 do
                            local inst = list[i]
                            if removeIds[inst.id] then
                                tok.properties:RemoveOngoingEffectBySeq(inst.seq)
                            elseif bind[inst.id] and t ~= nil then
                                local use = DeepCopy(inst.eotwMontageUse)
                                use.turnSeq = t.seq
                                inst.eotwMontageUse = use
                            end
                        end
                    end,
                }
            end)
            DropHostPermissions()
            if not ok then
                printf("EotW montage: item effect upkeep failed for %s: %s", tostring(hero.name), tostring(err))
            end
        end

        --a consumable from the haul that has been used leaves the strip.
        for _, entry in ipairs(EncounterMontage.GetItems(hero.charid)) do
            local gearItem = (dmhub.GetTable("tbl_Gear") or {})[entry.itemid]
            if gearItem ~= nil and EquipmentCategory.IsConsumable(gearItem) then
                local have = InventoryQuantity(tok, entry.itemid)
                if have < (entry.qty or 1) then
                    UnrecordItem(doc, hero.charid, entry.itemid, (entry.qty or 1) - have)
                end
            end
        end
    end
end

--End every short effect a montage use left on the heroes, whatever turn it
--was waiting for. The host calls it when combat starts, as a backstop for a
--montage that never reached its own sweep.
function EncounterMontage.EndMontageUses()
    for _, hero in ipairs(EncounterMontage.Heroes()) do
        local tok = hero.token
        local seqs = {}
        for _, inst in ipairs(tok.properties:try_get("ongoingEffects", {})) do
            if type(inst:try_get("eotwMontageUse")) == "table" then
                seqs[#seqs + 1] = inst.seq
            end
        end
        if #seqs > 0 then
            ElevateToHostPermissions()
            pcall(function()
                tok:ModifyProperties{
                    description = "Montage: item effects end",
                    undoable = false,
                    execute = function()
                        for _, seq in ipairs(seqs) do
                            tok.properties:RemoveOngoingEffectBySeq(seq)
                        end
                    end,
                }
            end)
            DropHostPermissions()
        end
    end
end

--- what an item could do for the test at hand ---------------------------------
--While a hero stands at an entry, any item that would change something
--there -- reveal a secret option, open a knack, put an edge on the roll --
--raises an alert on its icon, and hovering it says what and lights up the
--options it helps (user direction 2026-10-09). Found by trying it: the
--item's effects are added to the hero as TRANSIENT built-in effects (the
--_tmp_ list RefreshToken rebuilds; never saved or sent), the same rules
--code is asked again, and the answers compared. Only the hero at the entry
--is weighed.

--Run fn(c) while `tok`'s creature also carries `effectids`.
function Consume.WithEffects(tok, effectids, fn)
    local c = tok.properties
    local saved = rawget(c, "_tmp_builtinOngoingEffects")
    local list = {}
    for _, e in ipairs(saved or {}) do
        list[#list + 1] = e
    end
    for i, effectid in ipairs(effectids) do
        list[#list + 1] = CharacterOngoingEffectInstance.new{
            ongoingEffectid = effectid,
            stacks = 1,
            seq = 100000 + i,
            id = string.format("eotw-try-%d", i),
            time = TimePoint.Create(),
        }
    end
    c._tmp_builtinOngoingEffects = list
    c:Invalidate()
    local ok, err = pcall(fn, c)
    c._tmp_builtinOngoingEffects = saved
    c:Invalidate()
    if not ok then
        printf("EotW montage: trying an item on failed: %s", tostring(err))
    end
end

--The names of the power-roll modifiers that would switch on for this
--hero's test of `version` ({ [name] = true }).
function Consume.ActiveRollModifiers(tok, version)
    local names = {}
    pcall(function()
        local _, skills = EncounterScript.ParseAttr(version.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
        local attrid = EncounterMontage.TestCharacteristic(tok.charid, version)
        if attrid == nil then
            return
        end
        local mods = tok.properties:GetModifiersForPowerRoll("2d10", "test_power_roll", { attribute = attrid, title = version.roll.name, skills = skills })
        for _, entry in ipairs(mods) do
            if entry.hint ~= nil and entry.hint.result and entry.modifier ~= nil then
                names[entry.modifier.name] = true
            end
        end
    end)
    return names
end

local g_benefitCache = {}
local BENEFIT_CACHE_SECONDS = 2

--What using this item now would do at the entry the hero is at:
--{ { text, optionIndex }, ... } (optionIndex nil for a secret option that
--would appear), or nil when it would change nothing here or no test is in
--hand. Client side, cached briefly.
function EncounterMontage.ItemBenefits(charid, itemid)
    local m = EncounterMontage.GetState()
    if m == nil or m.phase ~= "rounds" then
        return nil
    end
    local t = m.turn
    if t == nil or not (t.status == "scene" or t.status == "choosing") or t.heroid ~= charid then
        return nil
    end
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid or tok.properties == nil or tok.properties:GetItemQuantity(itemid) < 1 then
        return nil
    end

    local key = table.concat({ tostring(t.seq), tostring(t.status), tostring(t.optionIndex),
        tostring((t.delve or {}).obstacleId), tostring(m.consumeSeq), tostring(m.round) }, "|")
    local cacheKey = charid .. "|" .. itemid
    local cached = g_benefitCache[cacheKey]
    if cached ~= nil and cached.key == key and dmhub.Time() < cached.expires then
        return cached.result
    end

    local result = nil
    pcall(function()
        local beat = EncounterMontage.CurrentBeat()
        local entry = EncounterMontage.TurnEntry(beat, t)
        if entry == nil then
            return
        end
        local effectids, seen = {}, {}
        for _, use in ipairs(EncounterMontage.ConsumableUses(charid, itemid)) do
            if use.usable then
                local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
                local behaviors = Consume.BehaviorsForMode(item:try_get("consumable"), use.mode)
                for _, e in ipairs(Consume.EffectsOf(behaviors, tok.properties, 0)) do
                    if not seen[e.effectid] then
                        seen[e.effectid] = true
                        effectids[#effectids + 1] = e.effectid
                    end
                end
            end
        end
        if #effectids == 0 then
            return
        end

        local options = {}
        for i, option in ipairs(entry.options) do
            options[#options + 1] = { index = i, option = option }
        end
        --the languages of this scene's garbled lines: an item that teaches
        --one translates them (the stage does it in place).
        local garbledLangs = {}
        for _, step in ipairs((t.scene or {}).steps or {}) do
            if step.garbled and step.plain ~= nil and step.lang ~= nil then
                garbledLangs[step.lang] = true
            end
        end

        local function Evaluate()
            local out = {}
            out.langs = {}
            for lang, _ in pairs(garbledLangs) do
                out.langs[lang] = EncounterMontage.HeroSpeaks(t, lang)
            end
            for _, o in ipairs(options) do
                local rec = { visible = EncounterMontage.OptionVisible(charid, o.option) }
                rec.knack = EncounterMontage.KnackIndex(charid, o.option)
                local version = EncounterMontage.OptionForHero(charid, o.option)
                if rec.visible and version ~= nil and version.roll ~= nil then
                    local verdict = EncounterMontage.RiderVerdict(charid, o.option, version)
                    rec.net = verdict ~= nil and ((verdict.boons or 0) - (verdict.banes or 0)) or 0
                    rec.mods = Consume.ActiveRollModifiers(tok, version)
                end
                out[o.index] = rec
            end
            return out
        end

        local before = Evaluate()
        local after = nil
        Consume.WithEffects(tok, effectids, function(c)
            local facts = TestRiders.CreatureFacts(c)
            g_factsOverride[charid] = facts
            local ok, res = pcall(Evaluate)
            g_factsOverride[charid] = nil
            if ok then
                after = res
            end
        end)
        if after == nil then
            return
        end

        local benefits = {}
        for lang, _ in pairs(garbledLangs) do
            if (after.langs or {})[lang] and not (before.langs or {})[lang] then
                benefits[#benefits + 1] = { text = string.format("Lets you understand the %s being spoken.", lang) }
            end
        end
        for _, o in ipairs(options) do
            local b, a = before[o.index] or {}, after[o.index] or {}
            local name = o.option.name or "this option"
            if a.visible and not b.visible then
                benefits[#benefits + 1] = { text = "Could reveal a hidden option here." }
            elseif a.visible then
                if a.knack ~= nil and a.knack ~= b.knack then
                    benefits[#benefits + 1] = { text = string.format("Opens a knack for %s.", name), optionIndex = o.index }
                end
                if (a.net or 0) > (b.net or 0) then
                    local gain = (a.net or 0) - (b.net or 0)
                    benefits[#benefits + 1] = { text = string.format("%s on %s.", cond(gain >= 2, "A double edge", "An edge"), name), optionIndex = o.index }
                end
                for modName, _ in pairs(a.mods or {}) do
                    if not (b.mods or {})[modName] then
                        benefits[#benefits + 1] = { text = string.format("%s helps the test for %s.", modName, name), optionIndex = o.index }
                    end
                end
            end
        end
        if #benefits > 0 then
            result = benefits
        end
    end)

    g_benefitCache[cacheKey] = { key = key, result = result, expires = dmhub.Time() + BENEFIT_CACHE_SECONDS }
    return result
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
        --the entry's intro scene plays, then the hero chooses.
        m.turn = {
            seq = m.seq,
            userid = userid,
            heroid = hero.charid,
            heroName = hero.name,
            entryId = entry.id,
            status = "choosing",
            startedAt = dmhub.serverTime,
        }
        local t = m.turn
        if BuildScenePart(m, t, entry, nil, "intro") > 0 then
            t.status = "scene"
            t.sceneAfter = "choosing"
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
            return "ignored pass: inside a delve (turn back at the next choice)"
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
        if option == nil or (option.roll == nil and option.free == nil and (option.delve == nil or t.delve ~= nil)
            and EncounterMontage.KnackIndex(t.heroid, option) == nil) then
            return "ignored choose: no such option"
        end
        --option is only found when entry is.
        ---@cast entry -nil
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
        --an Allow rider the hero does not meet hides the option (a secret
        --option); the stage never sends this, but the host is the authority.
        local verdict = EncounterMontage.RiderVerdict(t.heroid, option, nil)
        if verdict ~= nil and not verdict.allowed then
            return string.format("ignored choose: %s does not meet '%s'", t.heroName, EncounterMontage.DescribeUnmet(verdict))
        end
        --the version this hero takes is fixed here, once: a knack the hero
        --meets replaces the option's roll (or removes it).
        local knackIndex = EncounterMontage.KnackIndex(t.heroid, option)
        local version = EncounterScript.OptionVersion(option, knackIndex)
        if version.roll == nil and version.free == nil then
            return "ignored choose: the option has nothing to take"
        end
        t.optionIndex = tonumber(req.optionIndex)
        t.optionName = option.name
        t.knackIndex = knackIndex
        t.knackReason = EncounterMontage.KnackReason(t.heroid, option, knackIndex)
        local after = "rolling"
        if version.roll == nil then
            after = "free"
        end
        --the option's own lines play before the dice come out.
        if version.preScene ~= nil and BuildScenePart(m, t, entry, version, "option") > 0 then
            t.status = "scene"
            t.sceneAfter = after
            return string.format("%s chooses %s", t.heroName, option.name)
        end
        if after == "free" then
            ResolveTurn(m, doc, t, entry, version, 0, heroes, userid)
            return string.format("%s chooses %s (no roll)", t.heroName, option.name)
        end
        StartRoll(m, t)
        return string.format("%s chooses %s", t.heroName, option.name)
    elseif kind == "cancel" then
        --backing out of the roll before the dice are thrown: back to the
        --options.
        local t = m.turn
        if t ~= nil and t.userid == userid and t.status == "rolling" and t.rollSeq == req.rollSeq then
            t.status = "choosing"
            t.rollSeq = nil
            t.optionIndex = nil
            t.optionName = nil
            t.knackIndex = nil
            t.knackReason = nil
            return "roll cancelled"
        end
        return "ignored cancel"
    elseif kind == "rolled" then
        local t = m.turn
        if t == nil or t.userid ~= userid or t.status ~= "rolling" or t.rollSeq ~= req.rollSeq then
            return "ignored roll: stale"
        end
        local entry = EncounterMontage.TurnEntry(beat, t)
        local option = EncounterMontage.TurnOption(entry, t)
        if option == nil or option.roll == nil then
            t.status = "choosing"
            return "ignored roll: option vanished"
        end
        --option is only found when entry is.
        ---@cast entry -nil
        local tierIndex = TierIndexForRoll(option.roll, req.tier, req.natural)
        --what the acting hero rolled WITH (perks such as Brawny and Pardon
        --My Friend ask which characteristic it was).
        t.attrid = req.attrid
        t.skillid = req.skillid
        t.total = req.total
        t.natural = req.natural
        t.baseTotal = req.total
        tierIndex = ApplyTierFloors(t, option, tierIndex)
        t.tier = tierIndex
        t.baseTier = tierIndex
        if tierIndex == 2 and tonumber(t.baseTotal) ~= nil and tonumber(t.baseTotal) < 12 then
            t.baseTotal = 12
        end

        --a failed test: perks that could rescue it are offered first.
        local offers = PerkOffersFor(m, t, option, heroes)
        if #offers > 0 then
            t.offers = offers
            t.offerOpenedAt = dmhub.serverTime
            t.status = "perk"
            return string.format("%s rolled tier %d on %s -- a perk may help", t.heroName, tierIndex, entry.name)
        end

        return AfterTestLanded(m, doc, t, beat, entry, option, heroes, userid)
    elseif kind == "perkUse" or kind == "perkPass" then
        local t = m.turn
        if t == nil or t.status ~= "perk" then
            return "ignored perk: not the moment"
        end
        local index = tonumber(req.offerIndex) or 0
        local offer = (t.offers or {})[index]
        local hero = offer ~= nil and HeroByCharid(heroes, offer.heroid) or nil
        if offer == nil or hero == nil or not UserControlsHero(userid, hero) then
            return "ignored perk: not your offer"
        end
        local entry = EncounterMontage.TurnEntry(beat, t)
        local option = EncounterMontage.TurnOption(entry, t)
        if entry == nil or option == nil or option.roll == nil then
            t.status = "choosing"
            return "ignored perk: option vanished"
        end
        if kind == "perkPass" then
            table.remove(t.offers, index)
            if #t.offers > 0 then
                return string.format("%s passes on %s", offer.heroName or "A hero", offer.perk)
            end
            return AfterTestLanded(m, doc, t, beat, entry, option, heroes, t.userid)
        end
        if offer.kind == "pardon" then
            --the other hero's own roll replaces the hero's (pardonRolled).
            m.seq = (m.seq or 0) + 1
            t.pardon = {
                userid = userid,
                heroid = offer.heroid,
                heroName = offer.heroName,
                rollSeq = m.seq,
                startedAt = dmhub.serverTime,
            }
            t.pardoned = true
            t.offers = nil
            t.offerOpenedAt = nil
            t.status = "pardon"
            return string.format("%s steps in for %s (Pardon My Friend)", offer.heroName or "A hero", t.heroName or "the hero")
        end
        UsePerkOffer(m, doc, t, offer, heroes)
        local note = string.format("%s uses %s", offer.heroName or "A hero", offer.perk)
        AfterTestLanded(m, doc, t, beat, entry, option, heroes, t.userid)
        return note
    elseif kind == "pardonRolled" or kind == "pardonCancel" then
        local t = m.turn
        local p = t ~= nil and t.pardon or nil
        if t == nil or p == nil or t.status ~= "pardon" or p.userid ~= userid or p.rollSeq ~= req.rollSeq then
            return "ignored pardon roll: stale"
        end
        local entry = EncounterMontage.TurnEntry(beat, t)
        local option = EncounterMontage.TurnOption(entry, t)
        t.pardon = nil
        if entry == nil or option == nil or option.roll == nil then
            t.status = "choosing"
            return "ignored pardon roll: option vanished"
        end
        if kind == "pardonCancel" then
            --backed out before the dice were thrown: the hero's own roll
            --stands, and the perk is still unspent for this test.
            t.pardoned = nil
            local offers = PerkOffersFor(m, t, option, heroes)
            if #offers > 0 then
                t.offers = offers
                t.offerOpenedAt = dmhub.serverTime
                t.status = "perk"
                return string.format("%s stays out of it", p.heroName or "A hero")
            end
            return AfterTestLanded(m, doc, t, beat, entry, option, heroes, t.userid)
        end
        local tierIndex = TierIndexForRoll(option.roll, req.tier, req.natural)
        t.total = req.total
        t.natural = req.natural
        t.baseTotal = req.total
        t.tier = tierIndex
        t.baseTier = tierIndex
        t.perkLines = t.perkLines or {}
        t.perkLines[#t.perkLines + 1] = string.format("Pardon My Friend: %s stepped in and rolled %s",
            p.heroName or "another hero", cond(tierIndex == 4, "a critical", string.format("tier %d", tierIndex)))
        --the new roll can fail too: the other perks get their chance at it.
        local offers = PerkOffersFor(m, t, option, heroes)
        if #offers > 0 then
            t.offers = offers
            t.offerOpenedAt = dmhub.serverTime
            t.status = "perk"
            return string.format("%s rolled tier %d in %s's place -- a perk may help", p.heroName or "A hero", tierIndex, t.heroName or "the hero")
        end
        AfterTestLanded(m, doc, t, beat, entry, option, heroes, t.userid)
        return string.format("%s rolled tier %d in %s's place (Pardon My Friend)", p.heroName or "A hero", tierIndex, t.heroName or "the hero")
    elseif kind == "bless" then
        --Ritualist: the hero at the entry blesses their own test (the ritual
        --needs a touch, and nobody else is there).
        local t = m.turn
        if t == nil or t.status ~= "choosing" or t.delve ~= nil then
            return "ignored bless: not the moment"
        end
        local hero = HeroByCharid(heroes, req.heroid)
        if hero == nil or not UserControlsHero(userid, hero) then
            return "ignored bless: not your hero"
        end
        if hero.charid ~= t.heroid then
            return "ignored bless: only the hero at the entry can bless the test"
        end
        local key = string.format("ritual:%d:%s", m.round or 1, hero.charid)
        if not EncounterMontage.HeroHasPerk(hero.charid, "Ritualist") or PerkUsed(m, key) or t.blessing ~= nil then
            return "ignored bless: no blessing to give"
        end
        MarkPerkUsed(m, key)
        t.blessing = { heroid = hero.charid, heroName = hero.name }
        return string.format("%s blesses %s (Ritualist)", hero.name, t.heroName or "the hero")
    elseif kind == "teamLeader" then
        --Team Leader: at the start of the montage, spend a hero token so
        --everyone tests with the leader's exploration skills.
        if m.phase ~= "rounds" or (m.round or 1) ~= 1 or next(m.acted or {}) ~= nil or m.teamLeader ~= nil then
            return "ignored team leader: not the moment"
        end
        local hero = HeroByCharid(heroes, req.heroid)
        if hero == nil or not UserControlsHero(userid, hero) or not EncounterMontage.HeroHasPerk(hero.charid, "Team Leader") then
            return "ignored team leader: not your hero"
        end
        local tokens = 0
        pcall(function() tokens = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) or 0 end)
        if tokens < 1 then
            return "ignored team leader: no hero token to spend"
        end
        pcall(function()
            CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, tokens - 1, string.format("%s: Team Leader", hero.name))
        end)
        local skills = {}
        pcall(function()
            for id, info in pairs(dmhub.GetTable(Skill.tableName) or {}) do
                local cat = nil
                pcall(function() cat = info.category end)
                if string.lower(cat or "") == "exploration" and hero.token.properties:ProficientInSkill(info) then
                    skills[#skills + 1] = id
                end
            end
        end)
        m.teamLeader = { heroid = hero.charid, heroName = hero.name, skills = skills }
        MarkPerkUsed(m, "teamleader:" .. hero.charid)
        return string.format("%s leads the party (Team Leader)", hero.name)
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
    elseif kind == "consumed" then
        --a player used one of their hero's items (EncounterMontage.ConsumeItem
        --cast it on their own client). The effects carry their own markers;
        --this only tells every stage to look again, since an item can change
        --what the hero at an entry is offered.
        local hero = HeroByCharid(heroes, req.heroid)
        if hero == nil or not UserControlsHero(userid, hero) then
            return "ignored consumed: not your hero"
        end
        m.consumeSeq = (m.consumeSeq or 0) + 1
        if req.aborted then
            return string.format("%s did not finish using %s", hero.name, tostring(req.item))
        end
        return string.format("%s used %s", hero.name, tostring(req.item))
    elseif kind == "chestRolling" then
        --the chest's dice are in the air: record them so every client's
        --chest card can follow the tumble (EncounterMontageStage.ChestCard).
        local t = m.turn
        if t == nil or t.delve == nil or t.status ~= "chest" or t.userid ~= userid or t.rollSeq ~= req.rollSeq then
            return "ignored chest dice: stale"
        end
        local guids = {}
        for _, guid in ipairs(req.guids or {}) do
            guids[#guids + 1] = tostring(guid)
        end
        t.chest = { guids = guids, mod = tonumber(req.mod) or 0 }
        return "chest dice rolling"
    elseif kind == "chestRolled" then
        --the roll has landed: the table rests on the row (revealing it if
        --the party has never seen it) until the hero clicks to take it.
        local t = m.turn
        if t == nil or t.delve == nil or t.status ~= "chest" or t.userid ~= userid or t.rollSeq ~= req.rollSeq then
            return "ignored chest roll: stale"
        end
        local delve = EncounterMontage.TurnDelve(t)
        local chest = delve ~= nil and delve.sections.chest or nil
        local total = math.floor(tonumber(req.total) or 1)
        local rows = (chest ~= nil and chest.table ~= nil and chest.table.rows) or {}
        local rowIndex = nil
        for i, row in ipairs(rows) do
            if total >= row.lo and total <= row.hi then
                rowIndex = i
                break
            end
        end
        t.chest = t.chest or {}
        t.chest.total = total
        t.chest.rowIndex = rowIndex
        t.chest.landedAt = dmhub.serverTime
        t.chest.newReveal = false
        if rowIndex ~= nil then
            local row = rows[rowIndex]
            t.chest.newReveal = not EncounterMontage.ChestRowSeen(t.delve.name, row)
            MarkChestRowSeen(doc, t.delve.name, row)
        end
        t.status = "chestlanded"
        return string.format("%s's chest roll lands on %d", t.heroName or "A hero", total)
    elseif kind == "chestTake" then
        local t = m.turn
        if t == nil or t.delve == nil or t.status ~= "chestlanded" or t.userid ~= userid or t.chest == nil then
            return "ignored chest take: not the moment"
        end
        local delve = EncounterMontage.TurnDelve(t)
        local chest = delve ~= nil and delve.sections.chest or nil
        local row = chest ~= nil and chest.table ~= nil and chest.table.rows[t.chest.rowIndex or 0] or nil
        local total = t.chest.total
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
        end
        t.delve.chests = (t.delve.chests or 0) + 1
        t.rollSeq = nil
        t.chest = nil
        --the find was just on show, so the Continue scene needs no lead line.
        DelveScene(m, doc, t, heroes, "continue", "delve-choice")
        return string.format("%s opens a chest: %s", t.heroName or "A hero", tostring(total))
    elseif kind == "delveOn" or kind == "delveOut" then
        local t = m.turn
        if t == nil or t.delve == nil or t.status ~= "delvechoice" or t.userid ~= userid then
            return "ignored delve choice: not the moment"
        end
        if kind == "delveOn" then
            local delve = EncounterMontage.TurnDelve(t)
            if not EncounterMontage.CanPressDeeper(t.heroid, delve) then
                return "ignored press deeper: no Recovery to spare"
            end
            local cost = EncounterMontage.DelvePressOnCost(delve)
            if cost > 0 then
                local applied = EncounterMontage.ApplyEffects({ { kind = "loserecovery", qty = cost } }, {
                    heroEntry = HeroByCharid(heroes, t.heroid),
                    userid = userid,
                    entryName = t.delve.entryName,
                    entryId = t.entryId,
                    montage = m,
                    doc = doc,
                })
                DelveAddApplied(t, applied)
            end
            DelveNextObstacle(m, doc, t, heroes)
            return string.format("%s presses deeper into %s", t.heroName or "A hero", t.delve.entryName or "the delve")
        end
        DelveLeave(m, doc, t, heroes, "leave")
        return string.format("%s turns back from %s", t.heroName or "A hero", t.delve.entryName or "the delve")
    elseif kind == "continue" then
        if m.phase ~= "consequences" then
            return "ignored continue"
        end
        if m.dice ~= nil then
            return "ignored continue: the dice are out"
        end
        return ApplyConsequence(m, doc, beat, userid, nil)
    elseif kind == "diceRolled" then
        --a player's dice for a table roll or a recovery loss have landed.
        local d = m.dice
        if d == nil or d.seq ~= req.diceSeq then
            return "ignored dice: stale"
        end
        for _, r in ipairs(d.rolls or {}) do
            if r.key == req.key then
                if r.total ~= nil then
                    return "ignored dice: already rolled"
                end
                if r.userid ~= userid then
                    return "ignored dice: not your roll"
                end
                local lo, hi = DiceRange(r.dice)
                r.total = math.max(lo, math.min(hi, math.floor(tonumber(req.total) or lo)))
                local line = string.format("%s rolls %d (%s, %s)", tostring(r.heroName), r.total, tostring(r.label), tostring(r.dice))
                local all = true
                for _, other in ipairs(d.rolls) do
                    if other.total == nil then
                        all = false
                    end
                end
                if all then
                    ResumeDice(m, doc, beat, heroes)
                end
                return line
            end
        end
        return "ignored dice: unknown roll"
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

--Host only. Heroes changed hands (a player left and the host took their
--heroes, they came back, or the host gave a hero away): the turn in
--progress follows. Whoever now controls the acting hero drives the turn,
--and the same goes for a Pardon My Friend re-roll. A
--roll already out stays with its roller unless that player is in `away`
--({ [userid] = true }); the new controller then rolls it afresh.
--Returns true when the turn changed.
function EncounterMontage.SyncTurnToOwners(away)
    away = away or {}
    local doc = EncounterMontage.GetDoc()
    local m = doc.data.montage
    if type(m) ~= "table" or type(m.turn) ~= "table" then
        return false
    end

    --the user who should hold a part of the turn now, or nil to leave it.
    local function NewHolder(current, charid, rollOut)
        if charid == nil then
            return nil
        end
        local tok = dmhub.GetCharacterById(charid)
        local owner = tok ~= nil and tok.ownerId or nil
        if owner == nil or owner == "PARTY" or owner == current then
            return nil
        end
        if rollOut and not away[current] then
            return nil
        end
        return owner
    end

    local t = m.turn
    local mainRollOut = t.status == "rolling" or t.status == "chest" or t.status == "chestlanded"
    local turnTo = NewHolder(t.userid, t.heroid, mainRollOut)
    local pardonTo = nil
    if type(t.pardon) == "table" then
        pardonTo = NewHolder(t.pardon.userid, t.pardon.heroid, t.status == "pardon")
    end
    if turnTo == nil and pardonTo == nil then
        return false
    end

    doc:BeginChange()
    t = doc.data.montage.turn
    if turnTo ~= nil then
        printf("EotW montage: %s's turn passes from %s to %s", tostring(t.heroName), tostring(t.userid), turnTo)
        t.userid = turnTo
    end
    if pardonTo ~= nil then
        t.pardon.userid = pardonTo
    end
    doc:CompleteChange("Montage: the turn changes hands", { undoable = false })
    return true
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
        printf("[EOTWPROF] server=%.3f app=%.3f host: opening beat opened (party in)", dmhub.serverTimeMilliseconds * 0.001, dmhub.Time())
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

    --a Pardon My Friend re-roll that never comes: the hero's own roll stands.
    if m.turn ~= nil and m.turn.status == "pardon" and m.turn.pardon ~= nil then
        local t = m.turn
        local age = dmhub.serverTime - (tonumber(t.pardon.startedAt) or dmhub.serverTime)
        if age >= PARDON_ROLL_SECONDS then
            printf("EotW montage: %s never rolled for Pardon My Friend; %s's roll stands",
                tostring(t.pardon.heroName), tostring(t.heroName))
            t.pardon = nil
            local entry = EncounterMontage.TurnEntry(beat, t)
            local option = EncounterMontage.TurnOption(entry, t)
            if entry ~= nil and option ~= nil and option.roll ~= nil then
                AfterTestLanded(m, doc, t, beat, entry, option, heroes, t.userid)
            else
                t.status = "choosing"
            end
        end
    end

    --a perk offer nobody answers closes itself: the test keeps its result
    --and moves on.
    if m.turn ~= nil and m.turn.status == "perk" then
        local t = m.turn
        local age = dmhub.serverTime - (tonumber(t.offerOpenedAt) or dmhub.serverTime)
        if age >= PERK_OFFER_SECONDS or #(t.offers or {}) == 0 then
            local entry = EncounterMontage.TurnEntry(beat, t)
            local option = EncounterMontage.TurnOption(entry, t)
            if entry ~= nil and option ~= nil and option.roll ~= nil then
                AfterTestLanded(m, doc, t, beat, entry, option, heroes, t.userid)
                printf("EotW montage: no perk used for %s; the result stands", tostring(t.heroName))
            else
                t.status = "choosing"
            end
        end
    end

    --dice nobody rolls: the host rolls them, and the wait is over.
    if m.dice ~= nil then
        local age = dmhub.serverTime - (tonumber(m.dice.openedAt) or dmhub.serverTime)
        if age >= DICE_ROLL_SECONDS then
            for _, r in ipairs(m.dice.rolls or {}) do
                if r.total == nil then
                    r.total = RollDiceExpression(r.dice)
                    printf("EotW montage: nobody rolled %s for %s; the host rolled %d", tostring(r.label), tostring(r.heroName), r.total)
                end
            end
            ResumeDice(m, doc, beat, heroes)
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
            m.lastApplied = LastTurnResult(m)
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

    --items used in the montage: short effects bound to the turn their hero
    --joins, ended when it resolves, swept when the rounds are over.
    local upkeepOk, upkeepErr = pcall(MaintainMontageUses, m, doc, heroes)
    if not upkeepOk then
        printf("EotW montage: item upkeep failed: %s", tostring(upkeepErr))
    end

    if resetRequested then
        doc.data.montage = nil
    end
    doc:CompleteChange("Montage tick", { undoable = false })

    if resetRequested then
        return "running"
    end
    --a montage that ended this tick lingers like one that ended earlier (the
    --check at the top of the tick): returning "done" at once started the next
    --beat in the same tick, so nobody saw the "over" card or the last results.
    local final = doc.data.montage
    if final ~= nil and final.phase == "done"
        and dmhub.serverTime - (tonumber(final.doneAt) or 0) >= DONE_LINGER_SECONDS then
        return "done"
    end
    return "running"
end

--- client tick ------------------------------------------------------------------

--the roll the local client has already launched, so a turn is rolled once.
local m_launchedRollSeq = nil
--the montage dice roll ("<seq>:<key>", see m.dice) this client has out.
local m_launchedDice = nil
--the m.dice seq this user has clicked Roll for. The dice wait on that
--click (the player is prompted, not rolled for); one click rolls all of
--this user's dice in that set.
local m_diceArmedSeq = nil

--True when m.dice has a die for this user that they have not yet clicked
--Roll for: the stage shows the Roll button while it is.
function EncounterMontage.MyDiceWaiting()
    local m = EncounterMontage.GetState()
    local d = m ~= nil and m.dice or nil
    if d == nil or m_diceArmedSeq == d.seq then
        return false
    end
    for _, r in ipairs(d.rolls or {}) do
        if r.total == nil and r.userid == dmhub.loginUserid then
            return true
        end
    end
    return false
end

--The Roll button: throw this user's montage dice (ClientTick launches them).
function EncounterMontage.RollMyDice()
    local m = EncounterMontage.GetState()
    if m ~= nil and m.dice ~= nil then
        m_diceArmedSeq = m.dice.seq
        EncounterMontage.ClientTick()
    end
end

--Roll this user's next montage die (a table roll, a hero's share of a
--recovery loss), one at a time: the next goes out once the host has
--recorded the last, so no request overwrites another.
local function LaunchMontageDice(d)
    if m_diceArmedSeq ~= d.seq then
        return
    end
    for _, r in ipairs(d.rolls or {}) do
        if r.total == nil and r.userid == dmhub.loginUserid then
            local mark = string.format("%s:%s", tostring(d.seq), tostring(r.key))
            if m_launchedDice == mark then
                return
            end
            m_launchedDice = mark
            local seq, key = d.seq, r.key
            dmhub.Roll{
                roll = r.dice or "1d6",
                description = string.format("%s: %s", r.heroName or "Hero", r.label or "Montage"),
                tokenid = r.heroid,
                complete = function(rollInfo)
                    if mod.unloaded then
                        return
                    end
                    --diceSeq, not seq: SendRequest numbers its requests in "seq".
                    EncounterMontage.SendRequest("diceRolled", { diceSeq = seq, key = key, total = rollInfo.total })
                end,
            }
            return
        end
    end
end

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
                --once the dice are thrown the result stands: no close (X) or
                --ESC back to the options, where a failed test could be retried.
                noCancelOnceThrown = true,
                --everyone else's read-only copy shows Accept / Re-roll as
                --ghost buttons they can click to ping at the roller ("spend
                --a hero token!").
                pingButtons = true,

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
local function ApplySkilledModifier(c, modifiers, skills)
    local usedSkillId = nil
    for _, m in ipairs(modifiers) do
        if m.modifier.name == "Skilled" then
            local skillNames = {}
            local found = false
            for _, skillid in ipairs(skills) do
                local skillInfo = dmhub.GetTable(Skill.tableName)[skillid]
                local lent = skillInfo ~= nil and not c:ProficientInSkill(skillInfo) and EncounterMontage.TeamLeaderGrants(skillid)
                if skillInfo ~= nil and (c:ProficientInSkill(skillInfo) or lent) then
                    found = true
                    usedSkillId = skillid
                    m.modifier = DeepCopy(m.modifier)
                    m.modifier.name = string.format(tr("Skilled in %s"), skillInfo.name)
                    if lent then
                        m.modifier.name = string.format("%s (Team Leader)", m.modifier.name)
                    end
                    m.modifier.description = string.format(tr("Skill in %s gives you +2 on this roll"), skillInfo.name)
                    m.modifier.activationCondition = true
                    m.hint.result = true
                    break
                elseif skillInfo ~= nil then
                    skillNames[#skillNames + 1] = skillInfo.name
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

--The characteristic a hero makes this option's test with: the best of the
--listed ones (Power Player may widen them).
function EncounterMontage.TestCharacteristic(charid, option)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid or tok.properties == nil or option == nil or option.roll == nil then
        return nil
    end
    local characteristics, skills = EncounterScript.ParseAttr(option.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
    characteristics = EncounterMontage.PerkCharacteristics(tok.properties, charid, characteristics, skills)
    local attrid = BestCharacteristic(tok.properties, characteristics)
    return attrid
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
--the perks ask about -- to the host.
local function LaunchRoll(turn, entry, option, heroToken)
    local c = heroToken.properties
    local characteristics, skills = EncounterScript.ParseAttr(option.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
    local title = string.format("%s: %s", option.roll.name, option.roll.attr)
    --Power Player: Might may stand in for any characteristic on a Brag,
    --Flirt or Intimidate test (EncounterMontage.PerkCharacteristics).
    characteristics = EncounterMontage.PerkCharacteristics(c, heroToken.charid, characteristics, skills)

    local attrid, bestModifier = BestCharacteristic(c, characteristics)
    if attrid == nil then
        printf("EotW montage: no characteristic matched '%s'; rolling with no bonus", option.roll.attr)
    end

    local rollType = "test_power_roll"
    local roll = string.format("2d10 + %d", bestModifier)
    local modifiers = {}
    if attrid ~= nil then
        --the test's skills go in the query, so a feature that grants an edge
        --on, say, Sneak tests (Wode Elf Glamor) turns on for a test that
        --lists Sneak, exactly as on a skill test from the character sheet.
        modifiers = c:GetModifiersForPowerRoll(roll, rollType, { attribute = attrid, title = title, skills = skills })
    end
    local usedSkillId = ApplySkilledModifier(c, modifiers, skills)
    local base = EncounterMontage.TurnBaseOption(entry, turn)
    AppendRiderModifiers(modifiers, EncounterMontage.RiderVerdict(heroToken.charid, base or option, option), rollType)
    EncounterMontage.AppendPerkModifiers(modifiers, c, heroToken.charid, turn, option, skills, attrid)

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

--Pardon My Friend: another hero makes the failed Presence test in the
--hero's place, with a bane, on the test's own tier table. Their own skill,
--edges and perks apply; the hero's blessing does not -- it is a new test,
--by someone else.
local function LaunchPardonRoll(turn, entry, option, token)
    local p = turn.pardon
    local c = token.properties
    local _, skills = EncounterScript.ParseAttr(option.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
    local attrid = AttrIdNamed("presence")
    local modifier = 0
    if attrid ~= nil then
        local attr = c:GetAttribute(attrid)
        if attr ~= nil then
            modifier = attr:Modifier()
        end
    end
    local title = string.format("%s (for %s): %s", option.roll.name, turn.heroName or "an ally", option.roll.attr)
    local rollType = "test_power_roll"
    local roll = string.format("2d10 + %d", modifier)
    local modifiers = {}
    if attrid ~= nil then
        modifiers = c:GetModifiersForPowerRoll(roll, rollType, { attribute = attrid, title = title, skills = skills })
    end
    ApplySkilledModifier(c, modifiers, skills)
    local base = EncounterMontage.TurnBaseOption(entry, turn)
    AppendRiderModifiers(modifiers, EncounterMontage.RiderVerdict(token.charid, base or option, option), rollType)
    EncounterMontage.AppendPerkModifiers(modifiers, c, token.charid, nil, option, skills, attrid)
    local bane = PerkChip("Bane: Pardon My Friend", "Pardon My Friend: stepping in for an ally, you take a bane.", "bane")
    if bane ~= nil then
        modifiers[#modifiers + 1] = bane
    end

    ShowMontageRoll {
        creature = c,
        heroToken = token,
        title = title,
        rollType = rollType,
        roll = roll,
        modifiers = modifiers,
        tiers = EncounterMontage.TeaserTiers(option.roll),
        rollSeq = p.rollSeq,
        expectedStatus = "pardon",
        CurrentRollSeq = function(t) return (t.pardon or {}).rollSeq end,
        completeKind = "pardonRolled",
        cancelKind = "pardonCancel",
    }
end

--Per-client: when it is this user's hero's turn to roll, show the roll
--dialog once per rollSeq. Called from the per-client driver and the stage.
function EncounterMontage.ClientTick()
    local m = EncounterMontage.GetState()
    --montage dice (a table roll, a recovery loss) come before anything else:
    --nothing else rolls while they are out.
    if m ~= nil and m.dice ~= nil then
        LaunchMontageDice(m.dice)
        return
    end
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
            --tell the host which dice are tumbling, so every client's chest
            --card can highlight the row they are landing on.
            begin = function(rollInfo)
                if mod.unloaded then
                    return
                end
                local guids = {}
                local flat = rollInfo.total or 0
                for _, r in ipairs(rollInfo.rolls or {}) do
                    guids[#guids + 1] = r.guid
                    flat = flat - (r.result or 0)
                end
                EncounterMontage.localChestDice = { rollSeq = seq, guids = guids, mod = flat }
                EncounterMontage.SendRequest("chestRolling", { rollSeq = seq, guids = guids, mod = flat })
            end,
            complete = function(rollInfo)
                if mod.unloaded then
                    return
                end
                EncounterMontage.SendRequest("chestRolled", { rollSeq = seq, total = rollInfo.total })
            end,
        }
        return
    end
    --the test itself or a Pardon My Friend re-roll: whichever roll is
    --waiting on THIS user, at most once per rollSeq.
    local pardoning = t.status == "pardon" and t.pardon ~= nil and t.pardon.userid == dmhub.loginUserid
    if not pardoning and (t.status ~= "rolling" or t.userid ~= dmhub.loginUserid) then
        return
    end
    local rollSeq = t.rollSeq
    if pardoning then
        rollSeq = t.pardon.rollSeq
    end
    if m_launchedRollSeq == rollSeq then
        return
    end
    local beat = EncounterMontage.CurrentBeat()
    if beat == nil then
        return
    end
    local entry = EncounterMontage.TurnEntry(beat, t)
    local option = EncounterMontage.TurnOption(entry, t)
    if option == nil or option.roll == nil then
        return
    end
    local rollerId = t.heroid
    if pardoning then
        rollerId = t.pardon.heroid
    end
    local heroToken = dmhub.GetCharacterById(rollerId)
    if heroToken == nil or not heroToken.valid then
        return
    end
    m_launchedRollSeq = rollSeq
    if pardoning then
        LaunchPardonRoll(t, entry, option, heroToken)
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
    --and every reinforcement that arrived.
    local reinforcements = rawget(_G, "EncounterReinforcements")
    if reinforcements ~= nil then
        pcall(function()
            for _, charid in ipairs(reinforcements.SpawnedTokens(doc)) do
                toDelete[#toDelete + 1] = charid
            end
        end)
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
        --and each encounter script undoes its own map changes (Rising Waters
        --drains). Every encounter on the map, not just the part being played:
        --on a series map an earlier part may have done the flooding.
        local seenEncounters = {}
        for _, mapEntry in ipairs(Encounter.GetEncountersOnCurrentMap(true)) do
            local encounter = mapEntry.encounter
            if encounter ~= nil and not seenEncounters[encounter] then
                seenEncounters[encounter] = true
                EncounterScript.ResetEncounter(encounter)
            end
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
    doc.data.reinforcements = nil
    doc.data.revealZones = nil
    doc.data.zonesRevealed = nil
    doc.data.startZones = nil
    doc.data.revealObjects = nil
    doc.data.objectsRevealed = nil
    doc.data.unlocked = nil
    doc.data.intelligence = nil
    doc.data.intelligenceByHero = nil
    doc.data.intelligenceLog = nil
    doc.data.prep = nil
    doc:CompleteChange("Montage test reset", { undoable = false })

    --EotW game: the combat flags and the map script's run-once state.
    local state = mod:GetDocumentSnapshot("eotwstate")
    if state.data.combatStarted ~= nil or state.data.proceedRequested ~= nil or state.data.arrange ~= nil
        or state.data.arrivalItems ~= nil then
        state:BeginChange()
        state.data.combatStarted = nil
        state.data.proceedRequested = nil
        state.data.arrange = nil
        state.data.arrivalItems = nil
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
                --the item snapshot the real host takes on arrival, so a
                --playtest's treasure is tracked like a real game's.
                pcall(function() EncounterOfTheWeekGame.EnsureArrivalItems() end)
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
