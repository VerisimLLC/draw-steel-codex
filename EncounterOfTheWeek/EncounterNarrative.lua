--Encounter of the Week: the narrative runtime.
--
--Runs a "# Narrative" beat of the map's script (EncounterScript.lua): the
--beat's "## sections" play one at a time, each showing its scene and its
--text and asking the party to choose. A section either has to be AGREED
--UPON (one choice per player; a split decision is settled at random, the
--stage flashing between the players before it lands) or is taken by EACH
--HERO ON THEIR OWN (one choice per hero). Everyone chooses before the
--section resolves and the next one begins. An option may carry the same
--rules text a montage power-roll tier can ("+1 hero token"), or nothing at
--all -- a plain "Proceed".
--
--Design: EncounterOfTheWeek.md, "Narrative beats".
--
--Authority model is the montage's: the HOST is the single writer of
--narrative.* state, from the map script's host tick
--(EncounterNarrative.HostTick). Players only stamp narrative.requests[userid]
--(EncounterNarrative.SendRequest) and the host validates and applies them in
--order. Nothing here is rolled, so there is no client tick.
--
--The shared document is the montage's ("eotwscript"), under its own key:
--  data.narrative = {
--    beatIndex, sectionIndex,
--    phase = "arriving"|"choosing"|"deciding"|"resolved"|"done",
--    choices = { [voterKey] = { optionIndex, userid, heroid, name, at } },
--                  -- voterKey is a userid ("together") or a hero charid
--                     ("individual"); see Voters().
--    decision = nil | { candidates = { { key, name, optionIndex, heroids }, ... },
--                       winner = voterKey, optionIndex, startedAt },
--                  -- a split agreed-upon choice: the stage flashes across the
--                     candidates until startedAt + DECIDE_FLASH_SECONDS, then
--                     the host resolves on the winner's option.
--    result = nil | { mode, optionIndex, optionName, decidedBy, applied = {...},
--                     groups = { { optionIndex, optionName, heroNames, applied }, ... } },
--    announce = nil | { feature, name, text, at },
--                  -- a feature this section just unlocked: the stage shows
--                     the explanation and blinks the pool it names, until the
--                     party presses on (see ActiveAnnounce).
--    resolvedAt, doneAt, startedAt (of the current section),
--    requests = { [userid] = { seq, kind, ... } }, handled = { [userid] = seq },
--    log = { { sectionId, sectionName, mode, optionName, applied }, ... },
--    seq = n,
--  }
--
--Effects land through EncounterMontage.ApplyEffects, so a narrative shares
--the montage's grant/damage/ally/malice/initiative machinery (and the hero
--card's haul strip, which reads data.items).

local mod = dmhub.GetModLoading()

EncounterNarrative = rawget(_G, "EncounterNarrative") or {}

local DOC_ID = "eotwscript"

--how long the stage flashes between the players before a split decision
--lands on one of them.
local DECIDE_FLASH_SECONDS = 3.2
--how long a resolved section stays on screen before the next one opens --
--long enough to read what it did, but only when it DID something. A plain
--"Proceed" (or any option whose rules text applied nothing) has nothing to
--read, so it moves on as soon as the press has registered: a story beat
--should feel like turning a page, not like waiting out a timer.
local RESOLVED_LINGER_SECONDS = 4
local RESOLVED_LINGER_QUIET = 0.4
--and how long the finished beat holds before the script moves on. The
--resolved panel above has already had its linger and the "done" phase shows
--the very same thing, so this is just enough not to look like a jump cut.
local DONE_LINGER_SECONDS = 0.3

EncounterNarrative.DECIDE_FLASH_SECONDS = DECIDE_FLASH_SECONDS

--- the document ------------------------------------------------------------

function EncounterNarrative.GetDoc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

--The live narrative state, or nil when no narrative beat is running.
function EncounterNarrative.GetState()
    local m = nil
    pcall(function() m = mod:GetDocumentSnapshot(DOC_ID).data.narrative end)
    if type(m) ~= "table" then
        return nil
    end
    return m
end

--The narrative beat the state is running, from the current map's script.
function EncounterNarrative.CurrentBeat()
    local m = EncounterNarrative.GetState()
    if m == nil then
        return nil, nil
    end
    local script = EncounterMontage.FindMapScript()
    local beat = script.parse.beats[m.beatIndex or 0]
    if beat == nil or beat.kind ~= "narrative" then
        return nil, script
    end
    return beat, script
end

--The section the state is on, and its index.
function EncounterNarrative.CurrentSection()
    local m = EncounterNarrative.GetState()
    local beat = EncounterNarrative.CurrentBeat()
    if m == nil or beat == nil then
        return nil, nil
    end
    local index = tonumber(m.sectionIndex) or 1
    return EncounterScript.NarrativeSections(beat)[index], index
end

--The backdrop for the section on screen: its own [[scene]] if it declared
--one, otherwise the beat's.
function EncounterNarrative.SceneImage(script, beat, section)
    if script == nil or script.doc == nil then
        return nil
    end
    local holder = (section ~= nil and section.sceneTag ~= nil) and section or beat
    if holder == nil or holder.sceneTag == nil then
        return nil
    end
    return EncounterMontage.SceneImage(script, holder)
end

--- voters ------------------------------------------------------------------

--Who has to choose in this section.
--  "individual": every hero, one choice each (key = hero charid).
--  "together":   every PLAYER, one choice each (key = userid), because the
--                choice is the party's, not a hero's -- a player running two
--                heroes still gets one voice. Heroes owned by the party
--                ("PARTY", the authoring game's pregens) collapse into a
--                single pseudo-voter that anyone at the table may fill.
--Returns { { key, name, kind = "hero"|"user", heroids = { charid, ... } }, ... }
function EncounterNarrative.Voters(section, heroes)
    heroes = heroes or EncounterMontage.Heroes()
    local result = {}
    if section ~= nil and section.mode == "individual" then
        for _, hero in ipairs(heroes) do
            result[#result + 1] = {
                key = hero.charid,
                name = hero.name,
                kind = "hero",
                heroids = { hero.charid },
                ownerId = hero.ownerId,
            }
        end
        return result
    end

    local byUser = {}
    for _, hero in ipairs(heroes) do
        local owner = hero.ownerId or "PARTY"
        local entry = byUser[owner]
        if entry == nil then
            local name = owner
            if owner == "PARTY" then
                name = "The party"
            else
                pcall(function() name = dmhub.GetDisplayName(owner) or owner end)
            end
            entry = { key = owner, name = name, kind = "user", heroids = {}, ownerId = owner }
            byUser[owner] = entry
            result[#result + 1] = entry
        end
        entry.heroids[#entry.heroids + 1] = hero.charid
    end
    table.sort(result, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.key < b.key
    end)
    return result
end

--The key this user votes under in an agreed-upon section, or nil when they
--control no hero at all (an observer).
function EncounterNarrative.VoterKeyForUser(userid, heroes)
    heroes = heroes or EncounterMontage.Heroes()
    local party = false
    for _, hero in ipairs(heroes) do
        if hero.ownerId == userid then
            return userid
        end
        if hero.ownerId == "PARTY" then
            party = true
        end
    end
    if party then
        return "PARTY"
    end
    return nil
end

--The voters who have not chosen yet, as display names.
function EncounterNarrative.PendingVoters(m, section, heroes)
    local pending = {}
    for _, voter in ipairs(EncounterNarrative.Voters(section, heroes)) do
        if ((m or {}).choices or {})[voter.key] == nil then
            pending[#pending + 1] = voter.name
        end
    end
    return pending
end

--The choice a hero's card should show: the hero's own in an individual
--section, their owner's in an agreed one. Returns the choice record or nil.
function EncounterNarrative.ChoiceForHero(m, section, heroEntry)
    if m == nil or heroEntry == nil then
        return nil
    end
    local choices = m.choices or {}
    if section ~= nil and section.mode == "individual" then
        return choices[heroEntry.charid]
    end
    return choices[heroEntry.ownerId or "PARTY"]
end

--- UI gates (the host re-checks everything) ---------------------------------

local function UserControlsHero(userid, heroEntry)
    if heroEntry == nil then
        return false
    end
    return heroEntry.ownerId == userid or heroEntry.ownerId == "PARTY"
end

--Is the narrative waiting on a choice this client can make right now?
function EncounterNarrative.LocalUserPendingChoice()
    local m = EncounterNarrative.GetState()
    if m == nil or m.phase ~= "choosing" then
        return false
    end
    local section = EncounterNarrative.CurrentSection()
    if section == nil then
        return false
    end
    local heroes = EncounterMontage.Heroes()
    if section.mode == "individual" then
        for _, hero in ipairs(heroes) do
            if EncounterNarrative.LocalUserCanChooseFor(hero.charid) then
                return true
            end
        end
        return false
    end
    local key = EncounterNarrative.VoterKeyForUser(dmhub.loginUserid, heroes)
    return key ~= nil and (m.choices or {})[key] == nil
end

--Individual sections: may the local user still choose for this hero? (The
--drag gate on the hero card, the same shape as the montage's.)
function EncounterNarrative.LocalUserCanChooseFor(heroid)
    local m = EncounterNarrative.GetState()
    if m == nil or m.phase ~= "choosing" then
        return false
    end
    local section = EncounterNarrative.CurrentSection()
    if section == nil or section.mode ~= "individual" then
        return false
    end
    if (m.choices or {})[heroid] ~= nil then
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

--- requests (player side) ---------------------------------------------------

--Stamp a request for the host: {seq, kind, ...args}. One slot per user; a
--newer request replaces an unhandled older one.
function EncounterNarrative.SendRequest(kind, args)
    local userid = dmhub.loginUserid
    local doc = EncounterNarrative.GetDoc()
    if doc.data.narrative == nil then
        return false
    end
    doc:BeginChange()
    local m = doc.data.narrative
    m.requests = m.requests or {}
    local prev = m.requests[userid]
    local req = { seq = ((prev ~= nil and prev.seq) or 0) + 1, kind = kind, time = dmhub.serverTime }
    for k, v in pairs(args or {}) do
        req[k] = v
    end
    m.requests[userid] = req
    doc:CompleteChange("Narrative request: " .. tostring(kind), { undoable = false })
    return true
end

--Choose an option. heroid is required in an individual section (which hero
--is choosing) and ignored in an agreed-upon one.
function EncounterNarrative.Choose(optionIndex, heroid)
    return EncounterNarrative.SendRequest("choose", { optionIndex = optionIndex, heroid = heroid })
end

function EncounterNarrative.Unchoose(heroid)
    return EncounterNarrative.SendRequest("unchoose", { heroid = heroid })
end

--- effects ------------------------------------------------------------------

--A copy of an option's effects with every targeted clause aimed at the whole
--party: an agreed-upon option is the party's, so "You gain a Healing Potion"
--means all of them (user direction 2026-09-18). Untargeted clauses (malice,
--hero tokens, initiative) and "ally" are left alone -- one ally joins the
--party, not one per hero.
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

--- the stage ----------------------------------------------------------------
--One stage serves both beat kinds (it renders whichever the current beat
--is), so presenting and hiding go through the montage's helpers.

function EncounterNarrative.IsPresented()
    return EncounterMontage.IsPresented()
end

function EncounterNarrative.Present(beatIndex)
    EncounterMontage.Present(beatIndex)
end

function EncounterNarrative.Hide()
    EncounterMontage.Hide()
end

--- host tick ----------------------------------------------------------------

local function SectionsOf(beat)
    return EncounterScript.NarrativeSections(beat)
end

--"Unlock: Intelligence" turns on an optional feature of the game mode when
--its scene arrives: the beat's lines when the beat opens, a section's when
--that section does. Host, inside an OPEN change on the script document.
--
--A feature that just arrived is also ANNOUNCED: `narrative.announce` carries
--the explanation the stage shows and the pool the strip blinks, until the
--party presses on (EncounterNarrative.ActiveAnnounce).
local function ApplyUnlocks(doc, holder, sourceName)
    for _, u in ipairs((holder or {}).unlocks or {}) do
        if EncounterMontage.UnlockFeature(doc, u.feature, sourceName) then
            printf("EotW narrative: %s is unlocked (%s)", tostring(u.name), tostring(sourceName))
            local record = EncounterScript.FEATURES[u.feature]
            if doc.data.narrative ~= nil and record ~= nil and record.explanation ~= nil then
                doc.data.narrative.announce = {
                    feature = u.feature,
                    name = record.name,
                    text = record.explanation,
                    at = dmhub.serverTime,
                }
            end
        end
    end
end

--The feature-unlock callout that should be on screen right now, or nil.
--Every client reads it off the shared state, so the explanation and the blink
--round the pool it names start and stop together on all of them -- and a
--client that joins mid-section still gets the explanation.
--
--It stands for as long as the section it arrived on is still asking: the
--party reads it and presses on, and pressing on is what dismisses it. No
--timer -- a callout that timed out would go while somebody was still reading.
function EncounterNarrative.ActiveAnnounce()
    local m = EncounterNarrative.GetState()
    local announce = m ~= nil and m.announce or nil
    if type(announce) ~= "table" or announce.text == nil then
        return nil
    end
    if m.phase ~= "arriving" and m.phase ~= "choosing" then
        return nil
    end
    return announce
end

local function OptionName(section, index)
    local option = (section ~= nil and section.options[index]) or nil
    return (option ~= nil and option.name) or "?"
end

--Everyone who must choose has chosen.
local function ChoicesComplete(m, section, heroes)
    local voters = EncounterNarrative.Voters(section, heroes)
    if #voters == 0 then
        return false
    end
    for _, voter in ipairs(voters) do
        if (m.choices or {})[voter.key] == nil then
            return false
        end
    end
    return true
end

--Apply a section's outcome and park the state on "resolved".
--optionIndex is the agreed option (together) and nil for individual, where
--each option is applied once for the heroes who chose it.
local function ResolveSection(m, doc, beat, section, heroes, optionIndex, decidedBy)
    local log = {
        sectionId = section.id,
        sectionName = section.name,
        mode = section.mode,
        at = dmhub.serverTime,
    }
    local result = { mode = section.mode }

    if section.mode == "individual" then
        --group the heroes by the option they took; each option is applied
        --once, so a party-wide clause on it does not land four times.
        local order = {}
        local byOption = {}
        for _, hero in ipairs(heroes) do
            local choice = (m.choices or {})[hero.charid]
            local index = choice ~= nil and tonumber(choice.optionIndex) or nil
            if index ~= nil and section.options[index] ~= nil then
                if byOption[index] == nil then
                    byOption[index] = { optionIndex = index, optionName = OptionName(section, index), heroes = {}, heroNames = {} }
                    order[#order + 1] = index
                end
                local group = byOption[index]
                group.heroes[#group.heroes + 1] = hero
                group.heroNames[#group.heroNames + 1] = hero.name
            end
        end
        table.sort(order)
        result.groups = {}
        for _, index in ipairs(order) do
            local group = byOption[index]
            local applied, newAllies = EncounterMontage.ApplyEffects(section.options[index].effects, {
                heroEntries = group.heroes,
                heroEntry = group.heroes[1],
                userid = group.heroes[1] ~= nil and group.heroes[1].ownerId or nil,
                entryName = section.name,
                source = "Narrative",
                doc = doc,
            })
            for _, charid in ipairs(newAllies or {}) do
                EncounterMontage.RecordAlly(doc, group.heroes[1].charid, charid)
            end
            result.groups[#result.groups + 1] = {
                optionIndex = index,
                optionName = group.optionName,
                heroNames = group.heroNames,
                applied = applied,
            }
        end
        log.groups = result.groups
    else
        local option = section.options[optionIndex]
        local anchor = nil
        if decidedBy ~= nil then
            for _, hero in ipairs(heroes) do
                if hero.ownerId == decidedBy then
                    anchor = hero
                    break
                end
            end
        end
        anchor = anchor or heroes[1]
        local applied, newAllies = EncounterMontage.ApplyEffects(PartyScoped(option ~= nil and option.effects or {}), {
            heroEntry = anchor,
            userid = anchor ~= nil and anchor.ownerId or nil,
            entryName = section.name,
            source = "Narrative",
            doc = doc,
        })
        for _, charid in ipairs(newAllies or {}) do
            EncounterMontage.RecordAlly(doc, anchor.charid, charid)
        end
        result.optionIndex = optionIndex
        result.optionName = OptionName(section, optionIndex)
        result.decidedBy = decidedBy
        result.applied = applied
        log.optionName = result.optionName
        log.applied = applied
        log.decidedBy = decidedBy
    end

    --did anything actually land? A section whose option had no rules text
    --resolves to nothing worth reading, and should not hold the screen.
    local applied = #(result.applied or {})
    for _, group in ipairs(result.groups or {}) do
        applied = applied + #(group.applied or {})
    end

    m.result = result
    m.phase = "resolved"
    m.resolvedLinger = cond(applied > 0, RESOLVED_LINGER_SECONDS, RESOLVED_LINGER_QUIET)
    m.resolvedAt = dmhub.serverTime
    m.log = m.log or {}
    m.log[#m.log + 1] = log
    m.seq = (tonumber(m.seq) or 0) + 1
end

--A split agreed-upon vote: the host picks a player at random and records the
--candidates so every client can flash between them before it lands.
local function BeginDecision(m, section, heroes)
    local candidates = {}
    for _, voter in ipairs(EncounterNarrative.Voters(section, heroes)) do
        local choice = (m.choices or {})[voter.key]
        if choice ~= nil then
            candidates[#candidates + 1] = {
                key = voter.key,
                name = voter.name,
                optionIndex = choice.optionIndex,
                optionName = OptionName(section, choice.optionIndex),
                heroids = voter.heroids,
            }
        end
    end
    if #candidates == 0 then
        return false
    end
    local winner = candidates[math.random(#candidates)]
    m.decision = {
        candidates = candidates,
        winner = winner.key,
        winnerName = winner.name,
        optionIndex = winner.optionIndex,
        optionName = winner.optionName,
        startedAt = dmhub.serverTime,
    }
    m.phase = "deciding"
    m.seq = (tonumber(m.seq) or 0) + 1
    printf("EotW narrative: the party is split; %s decides (%s)", tostring(winner.name), tostring(winner.optionName))
    return true
end

--Validate and apply one player request. Returns a line to log, or nil.
local function HandleRequest(m, doc, userid, req, beat, heroes)
    local sections = SectionsOf(beat)
    local section = sections[tonumber(m.sectionIndex) or 1]
    if section == nil then
        return nil
    end
    if m.phase ~= "choosing" then
        return nil
    end

    if req.kind == "choose" or req.kind == "unchoose" then
        local key = nil
        local name = nil
        if section.mode == "individual" then
            local hero = nil
            for _, h in ipairs(heroes) do
                if h.charid == req.heroid then
                    hero = h
                end
            end
            if hero == nil then
                return string.format("%s chose for an unknown hero", tostring(userid))
            end
            if not UserControlsHero(userid, hero) then
                return string.format("%s does not control %s", tostring(userid), tostring(hero.name))
            end
            key, name = hero.charid, hero.name
        else
            key = EncounterNarrative.VoterKeyForUser(userid, heroes)
            if key == nil then
                return string.format("%s controls no hero and cannot choose", tostring(userid))
            end
            name = key == "PARTY" and "The party" or nil
            if name == nil then
                pcall(function() name = dmhub.GetDisplayName(key) or key end)
            end
        end

        m.choices = m.choices or {}
        if req.kind == "unchoose" then
            m.choices[key] = nil
            m.seq = (tonumber(m.seq) or 0) + 1
            return string.format("%s took their choice back", tostring(name))
        end

        local index = tonumber(req.optionIndex)
        if index == nil or section.options[index] == nil then
            return string.format("%s chose option %s, which does not exist", tostring(name), tostring(req.optionIndex))
        end
        m.choices[key] = {
            optionIndex = index,
            userid = userid,
            heroid = req.heroid,
            name = name,
            at = dmhub.serverTime,
        }
        m.seq = (tonumber(m.seq) or 0) + 1
        return string.format("%s chose '%s'", tostring(name), OptionName(section, index))
    end

    return nil
end

--Seed the state for a narrative beat and put the stage up. The beat opens in
--"arriving": the stage is on screen (it is what the loading screen reveals)
--but nobody can choose until the host tick -- which only runs once every
--player is in -- opens the first section.
function EncounterNarrative.Begin(script, beat, beatIndex)
    local doc = EncounterNarrative.GetDoc()
    doc:BeginChange()
    doc.data.narrative = {
        beatIndex = beatIndex,
        sectionIndex = 1,
        phase = "arriving",
        choices = {},
        requests = {},
        handled = {},
        log = {},
        startedAt = dmhub.serverTime,
        seq = 0,
    }
    doc.data.stageDismissAt = nil
    ApplyUnlocks(doc, beat, beat.title or "Narrative")
    doc:CompleteChange("Narrative started", { undoable = false })
    printf("EotW narrative: beat %d started (%d sections)", beatIndex, EncounterScript.SectionCount(beat))
    EncounterNarrative.Present(beatIndex)
end

--Run the narrative beat from the host tick. Returns "running" while it plays
--and "done" once the last section has resolved.
function EncounterNarrative.HostTick(script, beat, beatIndex)
    local doc = EncounterNarrative.GetDoc()
    local m = doc.data.narrative
    if type(m) ~= "table" or m.beatIndex ~= beatIndex then
        EncounterNarrative.Begin(script, beat, beatIndex)
        return "running"
    end

    if m.phase == "arriving" then
        doc:BeginChange()
        doc.data.narrative.phase = "choosing"
        doc.data.narrative.startedAt = dmhub.serverTime
        --the first section is now on screen: whatever it unlocks arrives
        --with it. (The beat's own unlocks landed in Begin.)
        local first = SectionsOf(beat)[tonumber(doc.data.narrative.sectionIndex) or 1]
        if first ~= nil then
            ApplyUnlocks(doc, first, first.name)
        end
        doc:CompleteChange("Narrative: the party has arrived", { undoable = false })
        m = doc.data.narrative
        printf("EotW narrative: beat %d -- the party has arrived", beatIndex)
    end

    if m.phase == "done" then
        local age = dmhub.serverTime - (tonumber(m.doneAt) or 0)
        if age >= DONE_LINGER_SECONDS then
            return "done"
        end
        return "running"
    end

    if not EncounterNarrative.IsPresented() then
        EncounterNarrative.Present(beatIndex)
    end

    local heroes = EncounterMontage.Heroes()
    local sections = SectionsOf(beat)

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
    m = doc.data.narrative
    for _, p in ipairs(pending) do
        m.handled = m.handled or {}
        m.handled[p.userid] = p.req.seq
        if p.req.kind == "reset" then
            resetRequested = true
        else
            local ok, result = pcall(HandleRequest, m, doc, p.userid, p.req, beat, heroes)
            if not ok then
                printf("EotW narrative: request %s from %s failed: %s", tostring(p.req.kind), tostring(p.userid), tostring(result))
            elseif result ~= nil then
                printf("EotW narrative: %s", tostring(result))
            end
        end
    end

    local section = sections[tonumber(m.sectionIndex) or 1]

    --everyone has chosen: agree, or settle it at random.
    if m.phase == "choosing" and section ~= nil and ChoicesComplete(m, section, heroes) then
        if section.mode == "individual" then
            ResolveSection(m, doc, beat, section, heroes, nil, nil)
        else
            local first, split = nil, false
            for _, voter in ipairs(EncounterNarrative.Voters(section, heroes)) do
                local choice = (m.choices or {})[voter.key]
                local index = choice ~= nil and tonumber(choice.optionIndex) or nil
                if first == nil then
                    first = index
                elseif index ~= first then
                    split = true
                end
            end
            if split then
                if not BeginDecision(m, section, heroes) then
                    ResolveSection(m, doc, beat, section, heroes, first or 1, nil)
                end
            else
                ResolveSection(m, doc, beat, section, heroes, first or 1, nil)
            end
        end
    end

    --the flash across the players has run its course: the winner's option
    --is the party's.
    if m.phase == "deciding" and m.decision ~= nil and section ~= nil then
        local age = dmhub.serverTime - (tonumber(m.decision.startedAt) or dmhub.serverTime)
        if age >= DECIDE_FLASH_SECONDS then
            ResolveSection(m, doc, beat, section, heroes, tonumber(m.decision.optionIndex) or 1, m.decision.winner)
        end
    end

    --a resolved section lingers so everyone reads the outcome, then the next
    --one opens.
    if m.phase == "resolved" then
        local age = dmhub.serverTime - (tonumber(m.resolvedAt) or dmhub.serverTime)
        if age >= (tonumber(m.resolvedLinger) or RESOLVED_LINGER_SECONDS) then
            local nextIndex = (tonumber(m.sectionIndex) or 1) + 1
            if sections[nextIndex] == nil then
                m.phase = "done"
                m.doneAt = dmhub.serverTime
                printf("EotW narrative: beat %d complete", beatIndex)
            else
                m.sectionIndex = nextIndex
                m.phase = "choosing"
                m.choices = {}
                m.decision = nil
                m.result = nil
                --the previous section's callout goes with it (the next
                --section may hang one of its own, below).
                m.announce = nil
                m.resolvedAt = nil
                m.resolvedLinger = nil
                m.startedAt = dmhub.serverTime
                m.seq = (tonumber(m.seq) or 0) + 1
                ApplyUnlocks(doc, sections[nextIndex], sections[nextIndex].name)
                printf("EotW narrative: section %d -- %s", nextIndex, tostring(sections[nextIndex].name))
            end
        end
    end

    if resetRequested then
        doc.data.narrative = nil
    end
    doc:CompleteChange("Narrative tick", { undoable = false })

    if resetRequested then
        return "running"
    end
    if doc.data.narrative ~= nil and doc.data.narrative.phase == "done" then
        return "done"
    end
    return "running"
end

--Host: throw the current section's outcome without waiting for a missing
--player (the dev command; see EncounterOfTheWeek.md "Narrative beats").
function EncounterNarrative.ForceResolve()
    local m = EncounterNarrative.GetState()
    local beat = EncounterNarrative.CurrentBeat()
    if m == nil or beat == nil or m.phase ~= "choosing" then
        return false, "no section is waiting for a choice"
    end
    local heroes = EncounterMontage.Heroes()
    local section = SectionsOf(beat)[tonumber(m.sectionIndex) or 1]
    if section == nil then
        return false, "no section"
    end
    local doc = EncounterNarrative.GetDoc()
    doc:BeginChange()
    local state = doc.data.narrative
    local chosen = nil
    for _, choice in pairs(state.choices or {}) do
        chosen = tonumber(choice.optionIndex) or chosen
    end
    if section.mode == "individual" then
        ResolveSection(state, doc, beat, section, heroes, nil, nil)
    else
        ResolveSection(state, doc, beat, section, heroes, chosen or 1, nil)
    end
    doc:CompleteChange("Narrative: forced", { undoable = false })
    return true
end

--- dev driver ----------------------------------------------------------------

--Outside a real EotW game there is no map-script host tick, so
--"/eotwnarrative start" runs one here: the first narrative beat of the
--current map's script, ticked every 0.5s until it reports done.
local m_devDriver = nil

function EncounterNarrative.StartDevDriver()
    if m_devDriver ~= nil and m_devDriver.running then
        print("EotW narrative: dev driver already running")
        return
    end
    local driver = { running = true }
    m_devDriver = driver
    dmhub.Coroutine(function()
        while driver.running and not mod.unloaded do
            local script = EncounterMontage.FindMapScript()
            local beat, index = nil, nil
            for i, b in ipairs(script.parse.beats) do
                if b.kind == "narrative" then
                    beat, index = b, i
                    break
                end
            end
            if beat == nil then
                print("EotW narrative: this map's script has no narrative beat")
                break
            end
            local ok, status = pcall(EncounterNarrative.HostTick, script, beat, index)
            if not ok then
                printf("EotW narrative: dev driver tick failed: %s", tostring(status))
            elseif status == "done" then
                print("EotW narrative: narrative complete (dev driver)")
                EncounterNarrative.Hide()
                break
            end
            coroutine.yield(0.5)
        end
        driver.running = false
    end)
    print("EotW narrative: dev driver started")
end

function EncounterNarrative.StopDevDriver()
    if m_devDriver ~= nil then
        m_devDriver.running = false
    end
    m_devDriver = nil
end

--- dev commands --------------------------------------------------------------

--"/eotwnarrative start|stop|state|force|reset"
local function PrintState()
    local m = EncounterNarrative.GetState()
    if m == nil then
        print("EotW narrative: no narrative is running")
        return
    end
    local beat = EncounterNarrative.CurrentBeat()
    local section, index = EncounterNarrative.CurrentSection()
    printf("EotW narrative: beat %s, section %s (%s), phase %s",
        tostring(m.beatIndex), tostring(index),
        tostring(section ~= nil and section.name or "?"),
        tostring(m.phase))
    if beat == nil then
        print("  (the current beat is not a narrative)")
    end
    if section ~= nil then
        printf("  mode: %s", tostring(section.mode))
        for i, option in ipairs(section.options) do
            printf("  option %d: %s (%d effects)", i, option.name, #option.effects)
        end
        for _, voter in ipairs(EncounterNarrative.Voters(section, nil)) do
            local choice = (m.choices or {})[voter.key]
            printf("  voter %s (%s): %s", tostring(voter.name), tostring(voter.key),
                cond(choice ~= nil, "option " .. tostring(choice ~= nil and choice.optionIndex), "waiting"))
        end
    end
    if m.decision ~= nil then
        printf("  decision: %s wins with '%s'", tostring(m.decision.winnerName), tostring(m.decision.optionName))
    end
end

pcall(function()
    Commands.RegisterMacro{
        name = "eotwnarrative",
        summary = "inspect, drive or reset the Encounter of the Week narrative beat",
        doc = "Usage: /eotwnarrative start | stop | state | force | reset\nstart runs this map's first narrative beat right here (a dev host tick, for the authoring game); stop halts that driver; state prints who has chosen and who is still to; force resolves the section on the choices already in (a missing player); reset clears the narrative state.",
        command = function(str)
            local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
            if arg == "start" then
                EncounterNarrative.StartDevDriver()
            elseif arg == "stop" then
                EncounterNarrative.StopDevDriver()
                print("EotW narrative: dev driver stopped")
            elseif arg == "force" then
                local ok, err = EncounterNarrative.ForceResolve()
                printf("EotW narrative: force -> %s", tostring(ok and "resolved" or err))
            elseif arg == "reset" then
                local doc = EncounterNarrative.GetDoc()
                doc:BeginChange()
                doc.data.narrative = nil
                doc:CompleteChange("Narrative reset", { undoable = false })
                print("EotW narrative: state cleared")
            elseif arg == "json" then
                print(json(EncounterNarrative.GetState()))
            else
                PrintState()
            end
        end,
    }
end)
