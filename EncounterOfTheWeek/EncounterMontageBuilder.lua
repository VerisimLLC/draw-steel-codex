local mod = dmhub.GetModLoading()

--Encounter of the Week: the Montage Builder.
--
--A Director's window for building and editing a map's montage without
--writing the script markdown by hand. The markdown stays the source of
--truth: every change here is a small line patch (EncounterScriptEdit) on
--the journal document the edited text came from -- the master script or one
--of its sub-documents -- uploaded at once, and the script is re-parsed with
--the runtime's own parser after every change, so what the builder shows is
--exactly what the game will play.
--Design: EncounterOfTheWeek.md, "The montage builder".
--
--Open it from the Game menu ("Montage Builder") or with /eotwbuilder.

EncounterMontageBuilder = {}
local B = EncounterMontageBuilder
local E = EncounterScriptEdit

local RULE_COLOR = "#7fd97f"
local PROBLEM_COLOR = "#e88a8a"
local OPPORTUNITY_COLOR = "#6fae7a"
local THREAT_COLOR = "#c46a6a"
local OBSTACLE_COLOR = "#a08ac4"

local CHARACTERISTICS = { "Might", "Agility", "Reason", "Intuition", "Presence" }
local TIER_RANGES = { "11 or lower", "12-16", "17+", "Critical (natural 19-20)" }

local function trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function lower(s)
    return string.lower(s or "")
end

local function DocText(doc)
    local text = ""
    if doc ~= nil then
        pcall(function() text = doc:GetTextContent() or "" end)
    end
    return text
end

local function DocsTable()
    return dmhub.GetTable("documents") or {}
end

--- the session: what is open, its text, and undo --------------------------------
--
--session = {
--  rootId, mapid,
--  texts = { [docid] = text },   -- the builder's copy of every document in the script
--  names = { [docid] = name },
--  pending = { [docid] = { name, doc } }, -- documents made here, not yet back from the server
--  parse,                         -- EncounterScript.ParseExpanded of texts
--  undo = { { texts = { [docid] = text before }, created = docid?, what } },
--  selected,                      -- see SelectedEntry
--  beatIndex,                     -- which montage beat the board shows
--  status,                        -- the last thing that happened, for the footer
--}

local function Resolver(session)
    return function(target)
        local key = lower(trim(target))
        key = string.match(key, "^document:(.+)$") or key
        for id, p in pairs(session.pending) do
            if lower(p.name) == key then
                return { id = id, name = p.name, text = session.texts[id] or "" }
            end
        end
        local r, why = EncounterMontage.ResolveScriptInclude(target, session.mapid)
        if r ~= nil then
            if session.texts[r.id] == nil then
                session.texts[r.id] = r.text
            end
            session.names[r.id] = r.name
            r.text = session.texts[r.id]
        end
        return r, why
    end
end

function B.Reparse(session)
    local expansion = EncounterScript.ExpandIncludes(
        { id = session.rootId, name = session.names[session.rootId], text = session.texts[session.rootId] },
        Resolver(session))
    session.parse = EncounterScript.ParseExpanded(expansion, session.rootId)
    --the montage beats, and the delves they lead into.
    session.montages = {}
    for i, beat in ipairs(session.parse.beats) do
        if beat.kind == "montage" then
            session.montages[#session.montages + 1] = { index = i, beat = beat }
        end
    end
    if session.beatIndex == nil or session.montages[session.beatIndex] == nil then
        session.beatIndex = 1
    end
end

--Open the current map's script (or the document `docid`). Returns the
--session, or nil + why.
function B.Load(docid)
    local mapid = game.currentMapId
    if docid == nil then
        local script = nil
        pcall(function() script = EncounterMontage.FindMapScript(true) end)
        docid = script ~= nil and script.docid or nil
    end
    if docid == nil then
        return nil, "This map has no Encounter of the Week script yet. Write a '# Montage' in a journal document filed under this map, then open the builder."
    end
    local doc = DocsTable()[docid]
    if doc == nil then
        return nil, "The script document is missing."
    end
    local session = {
        rootId = docid,
        mapid = mapid,
        texts = { [docid] = DocText(doc) },
        names = { [docid] = doc.description or "Script" },
        pending = {},
        uploading = {},
        undo = {},
        status = "",
    }
    B.Reparse(session)
    return session
end

--Write the changed documents back to the journal, a frame apart (a second
--upload to the same table in one frame is dropped). The first waits a
--little too, behind any document created or renamed this frame.
local function Upload(session, changed)
    local delay = 0.1
    for docid, text in pairs(changed) do
        local id, newText = docid, text
        session.uploading[id] = (session.uploading[id] or 0) + 1
        dmhub.Schedule(delay, function()
            session.uploading[id] = (session.uploading[id] or 1) - 1
            if session.uploading[id] <= 0 then
                session.uploading[id] = nil
            end
            if mod.unloaded then
                return
            end
            local doc = DocsTable()[id]
            if doc == nil and session.pending[id] ~= nil then
                --made here and not back from the server yet: send it whole again.
                doc = session.pending[id].doc
                doc:SetTextContent(newText)
                doc:Upload()
                return
            end
            if doc == nil then
                return
            end
            local original = DeepCopy(doc)
            doc:SetTextContent(newText)
            doc:Upload(original)
        end)
        delay = delay + 0.1
    end
end

--Apply an edit: patches from EncounterScriptEdit, or nil + why. Returns
--true when something was written.
function B.Commit(session, what, patches, why)
    if patches == nil then
        session.status = "Not changed: " .. tostring(why or "that edit could not be made")
        return false
    end
    if #patches == 0 then
        return false
    end
    local ok, changed = pcall(E.Apply, session.texts, patches)
    if not ok then
        session.status = "Not changed: " .. tostring(changed)
        return false
    end
    local before = {}
    local any = false
    for docid, text in pairs(changed) do
        if text ~= session.texts[docid] then
            before[docid] = session.texts[docid]
            session.texts[docid] = text
            any = true
        else
            changed[docid] = nil
        end
    end
    if not any then
        return false
    end
    session.undo[#session.undo + 1] = { texts = before, what = what }
    Upload(session, changed)
    B.Reparse(session)
    session.status = what
    return true
end

function B.Undo(session)
    local step = table.remove(session.undo)
    if step == nil then
        session.status = "Nothing to undo."
        return false
    end
    local changed = {}
    for docid, text in pairs(step.texts) do
        session.texts[docid] = text
        changed[docid] = text
    end
    Upload(session, changed)
    if step.renamed ~= nil then
        local r = step.renamed
        local doc = DocsTable()[r.docid]
        if doc ~= nil then
            local original = DeepCopy(doc)
            doc.description = r.name
            doc:Upload(original)
        end
        session.names[r.docid] = r.name
    end
    if step.created ~= nil then
        --a document this step made: hide it again.
        local id = step.created
        dmhub.Schedule(0.3, function()
            local doc = DocsTable()[id]
            if doc ~= nil then
                local original = DeepCopy(doc)
                doc.hidden = true
                doc:Upload(original)
            end
        end)
        session.pending[id] = nil
    end
    B.Reparse(session)
    session.status = "Undid: " .. tostring(step.what)
    return true
end

--Another client (or the journal) changed one of the documents: take its
--text. Returns true when anything changed.
function B.PollExternal(session)
    local docs = DocsTable()
    local changed = false
    for docid, text in pairs(session.texts) do
        local doc = docs[docid]
        if doc ~= nil and session.uploading[docid] == nil then
            local current = DocText(doc)
            if session.pending[docid] ~= nil then
                if current == text then
                    session.pending[docid] = nil
                end
            elseif current ~= text then
                session.texts[docid] = current
                changed = true
            end
        end
    end
    if changed then
        B.Reparse(session)
        session.status = "Updated from the journal."
    end
    return changed
end

--- finding things in the parse ---------------------------------------------------

--The montage beat the board shows (a parsed beat), or nil.
---@return table|nil
function B.CurrentBeat(session)
    local m = session.montages[session.beatIndex]
    return m ~= nil and m.beat or nil
end

--Every delve the current montage's options lead into, in the order they are first named.
function B.Delves(session)
    local list, seen = {}, {}
    local beat = B.CurrentBeat(session)
    if beat == nil then
        return list
    end
    for _, e in ipairs(EncounterScript.MontageEntries(beat)) do
        for _, o in ipairs(e.options) do
            if o.delve ~= nil then
                local key = EncounterScript.MatchKey(o.delve)
                local delve = session.parse.delves[key]
                if delve ~= nil and not seen[key] then
                    seen[key] = true
                    list[#list + 1] = { key = key, delve = delve }
                end
            end
        end
    end
    return list
end

--session.selected = { kind = "entry", round = i, index = j } (a montage
--entry) or { kind = "obstacle", delve = key, index = j }.
function B.SelectedEntry(session)
    local sel = session.selected
    if sel == nil then
        return nil
    end
    if sel.kind == "entry" then
        local beat = B.CurrentBeat(session)
        local round = beat ~= nil and beat.rounds[sel.round] or nil
        return round ~= nil and round.entries[sel.index] or nil
    end
    local delve = session.parse.delves[sel.delve]
    if delve == nil then
        return nil
    end
    if sel.kind == "section" then
        return delve.sections[sel.key]
    elseif sel.kind == "obstacle" then
        return delve.obstacles[sel.index]
    end
    return nil
end

--Parser warnings, keyed back to { docid, line }.
local function LocatedWarnings(session)
    local byName = {}
    for docid, name in pairs(session.names) do
        byName[name] = docid
    end
    local out = {}
    for _, w in ipairs(session.parse.warnings) do
        local name, line, rest = string.match(w, "^'(.-)' line (%d+): (.*)$")
        local docid = nil
        if name ~= nil then
            docid = byName[name]
        else
            line, rest = string.match(w, "^line (%d+): (.*)$")
            docid = session.rootId
        end
        --"unrecognized effect": prose the rules grammar did not match. Usually
        --deliberate flavour, so it is listed apart from real problems.
        local textOnly = string.find(w, "unrecognized effect", 1, true) ~= nil or string.find(w, "unrecognized consequence", 1, true) ~= nil
        out[#out + 1] = { text = w, message = rest or w, docid = docid, line = tonumber(line), textOnly = textOnly }
    end
    return out
end

--The warnings that fall inside the element headed at expanded line `line`.
function B.WarningsIn(session, line, level)
    local docid, first, last = E.ElementRange(session.parse, session.texts, line, level)
    local result = {}
    if docid == nil then
        return result
    end
    for _, w in ipairs(LocatedWarnings(session)) do
        if w.docid == docid and w.line ~= nil and w.line >= first and w.line <= last then
            result[#result + 1] = w
        end
    end
    return result
end

--The document an element lives in, by name.
function B.SourceName(session, line)
    local docid = E.Source(session.parse, line)
    return session.names[docid] or tostring(docid)
end

--"Presence (Persuade, Lie)" -> { "Presence" }, { "Persuade", "Lie" }
function B.SplitAttr(attr)
    local chars = {}
    local bare = lower(EncounterScript.AttrWithoutSkills(attr or ""))
    for _, c in ipairs(CHARACTERISTICS) do
        if string.find(bare, lower(c), 1, true) ~= nil then
            chars[#chars + 1] = c
        end
    end
    local skills = {}
    local inside = string.match(attr or "", "%((.*)%)")
    for token in string.gmatch(inside or "", "[^,]+") do
        if trim(token) ~= "" then
            skills[#skills + 1] = trim(token)
        end
    end
    return chars, skills
end

function B.SkillOptions()
    local options = {}
    for _, s in ipairs(Skill.skillsDropdownOptions or {}) do
        if type(s.text) == "string" and s.text ~= "" then
            options[#options + 1] = s.text
        end
    end
    table.sort(options)
    return options
end

--A name for a new entry document that no document in the map's folder
--already has.
local function UniqueDocName(session, base)
    local taken = {}
    for _, doc in unhidden_pairs(DocsTable()) do
        if type(doc.description) == "string" then
            taken[lower(doc.description)] = true
        end
    end
    for _, p in pairs(session.pending) do
        taken[lower(p.name)] = true
    end
    local name = base
    local n = 2
    while taken[lower(name)] do
        name = string.format("%s %d", base, n)
        n = n + 1
    end
    return name
end

--The rules a brand-new option starts with.
local function DefaultRoll(kind)
    if kind == "threat" then
        return E.RollLines{ name = "Test", attr = "Might (Endurance, Lift)",
            tiers = { { text = "You lose 3 stamina" }, { text = "The threat is vanquished" }, { text = "The threat is vanquished. +1 hero token" } } }
    end
    return E.RollLines{ name = "Test", attr = "Presence (Persuade, Empathize)",
        tiers = { { text = "Nothing comes of it" }, { text = "You gain 1 Healing Potion" }, { text = "+1 hero token" } } }
end

--Add a new entry to a round: its own sub-document, named after it, filed
--under the map, and an include line in the master under the round.
function B.AddEntry(session, roundIndex, kind)
    local beat = B.CurrentBeat(session)
    local round = beat ~= nil and beat.rounds[roundIndex] or nil
    if round == nil then
        return false
    end
    local base = cond(kind == "threat", "New Threat", "New Opportunity")
    local name = UniqueDocName(session, base)
    local block = E.EntryBlock{
        kind = kind,
        name = name,
        description = "Describe what the heroes find here.",
        consequence = kind == "threat" and "Each party member loses 3 stamina" or nil,
        options = { E.OptionBlock("Deal with it", "", DefaultRoll(kind)) },
    }

    --where the include line goes in the master: after the round's last
    --entry, else after its party-size lines, else after its heading.
    local parse = session.parse
    local rootLine = nil
    local last = round.entries[#round.entries]
    if last ~= nil then
        local docid = E.Source(parse, last.line)
        if docid == session.rootId then
            local _, _, lastLine = E.ElementRange(parse, session.texts, last.line, 2)
            rootLine = lastLine
        else
            rootLine = E.RootLine(parse, last.line)
        end
    elseif round.scaling ~= nil and #round.scaling > 0 then
        rootLine = E.RootLine(parse, round.scaling[#round.scaling].line)
    elseif not round.implicit then
        rootLine = E.RootLine(parse, round.line)
    elseif beat ~= nil then
        rootLine = E.RootLine(parse, beat.line)
    end
    if rootLine == nil then
        session.status = "Not added: could not find where the round sits in the master document."
        return false
    end

    local id = dmhub.GenerateGuid()
    local text = table.concat(block, "\n") .. "\n"
    local doc = MarkdownDocument.new{
        id = id,
        description = name,
        parentFolder = session.mapid,
        annotations = {},
    }
    doc:SetTextContent(text)
    doc:Upload()
    session.pending[id] = { name = name, doc = doc }
    session.names[id] = name
    session.texts[id] = text

    local patch = E.InsertBlockAfterDocLine(session.texts, session.rootId, rootLine, { E.IncludeLine(name) })
    if B.Commit(session, string.format("Added %s '%s'.", kind, name), { patch }) then
        session.undo[#session.undo].created = id
        --select it.
        local newBeat = B.CurrentBeat(session)
        local newRound = newBeat ~= nil and newBeat.rounds[roundIndex] or nil
        for j, e in ipairs(newRound ~= nil and newRound.entries or {}) do
            if e.name == name then
                session.selected = { kind = "entry", round = roundIndex, index = j }
            end
        end
        return true
    end
    return false
end

--Delete an entry. One that is the whole of its own sub-document goes with
--its include line, and the sub-document is hidden.
function B.DeleteEntry(session, entry)
    local parse = session.parse
    local docid, first, last = E.ElementRange(parse, session.texts, entry.line, 2)
    if docid == nil then
        return false
    end
    if docid ~= session.rootId then
        local lines = E.Split(session.texts[docid]).lines
        local onlyThis = true
        for i, l in ipairs(lines) do
            if (i < first or i > last) and trim(l) ~= "" then
                onlyThis = false
            end
        end
        if onlyThis then
            local rootLine = E.RootLine(parse, entry.line)
            if rootLine ~= nil then
                --take a blank line with the link when it sits between two,
                --so no gap is left where the entry was.
                local rootLines = E.Split(session.texts[session.rootId]).lines
                local last = rootLine
                if trim(rootLines[rootLine - 1] or "x") == "" and trim(rootLines[rootLine + 1] or "x") == "" then
                    last = rootLine + 1
                end
                local ok = B.Commit(session, string.format("Deleted '%s'.", entry.name), { E.Patch(session.rootId, rootLine, last, {}) })
                if ok then
                    local id = docid
                    dmhub.Schedule(0.3, function()
                        local doc = DocsTable()[id]
                        if doc ~= nil then
                            local original = DeepCopy(doc)
                            doc.hidden = true
                            doc:Upload(original)
                        end
                    end)
                    session.status = string.format("Deleted '%s' (its document '%s' is hidden; Undo restores the link only).", entry.name, tostring(session.names[docid]))
                end
                session.selected = nil
                return ok
            end
        end
    end
    local patches, why = E.DeleteElement(parse, session.texts, entry.line, 2)
    session.selected = nil
    return B.Commit(session, string.format("Deleted '%s'.", entry.name), patches, why)
end

--Is the entry the whole of its own sub-document? Returns that docid or nil.
local function OwnDocument(session, entry)
    local docid, first, last = E.ElementRange(session.parse, session.texts, entry.line, 2)
    if docid == nil or docid == session.rootId then
        return nil
    end
    for i, l in ipairs(E.Split(session.texts[docid]).lines) do
        if (i < first or i > last) and trim(l) ~= "" then
            return nil
        end
    end
    return docid
end

--Rename an entry. When the entry is the whole of a sub-document named
--after it, the document and the master's link to it are renamed too, so
--the journal keeps matching the board.
function B.RenameEntry(session, entry, name)
    name = E.LineText(name)
    if name == "" then
        session.status = "An entry needs a name."
        return false
    end
    local parse = session.parse
    local heading
    if entry.kind == "obstacle" then
        heading = "## Obstacle: " .. name
    else
        local e = { kind = entry.kind, name = name, required = entry.required, locked = entry.locked, temporary = entry.temporary }
        heading = E.EntryHeadingLine(e)
    end
    local headPatch, why = E.PatchExpanded(parse, entry.line, entry.line, { heading })
    if headPatch == nil then
        return B.Commit(session, "Renamed the entry.", nil, why)
    end
    local patches = { headPatch }

    local docid = OwnDocument(session, entry)
    local rootLine = docid ~= nil and E.RootLine(parse, entry.line) or nil
    local oldDocName = docid ~= nil and session.names[docid] or nil
    ---@type string|nil
    local renameDoc = nil
    if rootLine ~= nil and oldDocName ~= nil and lower(oldDocName) == lower(entry.name) then
        local linkLine = E.Split(session.texts[session.rootId]).lines[rootLine]
        local target = EncounterScript.IncludeTarget(linkLine or "")
        target = target ~= nil and (string.match(lower(target), "^document:(.+)$") or lower(target)) or nil
        local docName = (string.gsub(name, "[%[%]]", ""))
        if target == lower(oldDocName) and UniqueDocName(session, docName) == docName then
            patches[#patches + 1] = E.Patch(session.rootId, rootLine, rootLine, { E.IncludeLine(docName) })
            renameDoc = docName
        end
    end

    --the document first, so the new link resolves when the script is re-read.
    if renameDoc ~= nil and docid ~= nil then
        local doc = DocsTable()[docid]
        if doc ~= nil then
            local original = DeepCopy(doc)
            doc.description = renameDoc
            doc:Upload(original)
        elseif session.pending[docid] ~= nil then
            session.pending[docid].name = renameDoc
            session.pending[docid].doc.description = renameDoc
        end
        session.names[docid] = renameDoc
    end
    local ok = B.Commit(session, string.format("Renamed '%s' to '%s'.", entry.name, name), patches)
    if ok and renameDoc ~= nil then
        session.undo[#session.undo].renamed = { docid = docid, name = oldDocName }
    end
    return ok
end

--Add "## Round N+1" at the end of the montage beat (in the master).
function B.AddRound(session)
    local beat = B.CurrentBeat(session)
    if beat == nil then
        return false
    end
    local number = 1
    for _, r in ipairs(beat.rounds) do
        number = math.max(number, (r.number or 0) + 1)
    end
    local lastLine = nil
    local lastRound = beat.rounds[#beat.rounds]
    local lastEntry = lastRound ~= nil and lastRound.entries[#lastRound.entries] or nil
    local parse = session.parse
    if lastEntry ~= nil then
        if E.Source(parse, lastEntry.line) == session.rootId then
            local _, _, l = E.ElementRange(parse, session.texts, lastEntry.line, 2)
            lastLine = l
        else
            lastLine = E.RootLine(parse, lastEntry.line)
        end
    else
        lastLine = E.RootLine(parse, beat.line)
    end
    if lastLine == nil then
        return false
    end
    local block = { E.RoundHeadingLine(number) }
    return B.Commit(session, string.format("Added Round %d.", number),
        { E.InsertBlockAfterDocLine(session.texts, session.rootId, lastLine, block) })
end

--A patch (or nil + why) as a list for B.Commit.
local function One(patch, why)
    if patch == nil then
        return nil, why
    end
    return { patch }
end

--The last line of an option's (or knack's) rules: its roll block, else its
--free rules and riders. nil when it has neither.
function B.RulesEnd(holder)
    if holder.roll ~= nil then
        return holder.roll.lastLine
    end
    local last = nil
    if holder.free ~= nil then
        for _, l in ipairs(holder.free.lines or { holder.free.line }) do
            last = math.max(last or l, l)
        end
    end
    for _, r in ipairs(holder.riders or {}) do
        last = math.max(last or r.line, r.line)
    end
    return last
end

--Where a new entry of a round goes in the master: the master line after
--which it is inserted (after the round's last entry, else its party-size
--lines, else its heading). Optionally skips one entry (the one being moved).
local function RoundAnchor(session, roundIndex, skipEntry)
    local beat = B.CurrentBeat(session)
    local round = beat ~= nil and beat.rounds[roundIndex] or nil
    if round == nil then
        return nil
    end
    local parse = session.parse
    local last = nil
    for _, e in ipairs(round.entries) do
        if e ~= skipEntry then
            last = e
        end
    end
    if last ~= nil then
        if E.Source(parse, last.line) == session.rootId then
            local _, _, lastLine = E.ElementRange(parse, session.texts, last.line, 2)
            return lastLine
        end
        return E.RootLine(parse, last.line)
    elseif round.scaling ~= nil and #round.scaling > 0 then
        return E.RootLine(parse, round.scaling[#round.scaling].line)
    elseif not round.implicit then
        return E.RootLine(parse, round.line)
    elseif beat ~= nil then
        return E.RootLine(parse, beat.line)
    end
    return nil
end

--Move an entry to another round. An entry that is the whole of its own
--sub-document moves by its include line; one written in the master moves
--as its lines.
function B.MoveEntry(session, fromRound, index, toRound)
    local beat = B.CurrentBeat(session)
    local entry = beat ~= nil and beat.rounds[fromRound] ~= nil and beat.rounds[fromRound].entries[index] or nil
    if entry == nil or beat == nil or beat.rounds[toRound] == nil then
        return false
    end
    local parse = session.parse
    local anchor = RoundAnchor(session, toRound, entry)
    if anchor == nil then
        session.status = "Not moved: could not find the round in the master document."
        return false
    end
    local rootLines = E.Split(session.texts[session.rootId]).lines
    local docid, first, last = E.ElementRange(parse, session.texts, entry.line, 2)
    local lines, removeFirst, removeLast
    if docid == session.rootId then
        lines = E.ElementLines(parse, session.texts, entry.line, 2)
        removeFirst, removeLast = first, last
    elseif OwnDocument(session, entry) ~= nil then
        local link = E.RootLine(parse, entry.line)
        if link == nil then
            return false
        end
        lines = { rootLines[link] }
        removeFirst, removeLast = link, link
    else
        session.status = "Not moved: this entry shares its document with other text; move it as text."
        return false
    end
    --take the blank line after it too, when it would leave two in a row.
    if trim(rootLines[removeLast + 1] or "x") == "" and trim(rootLines[removeFirst - 1] or "x") == "" then
        removeLast = removeLast + 1
    end
    if anchor >= removeFirst - 1 and anchor <= removeLast then
        session.status = "It is already there."
        return false
    end
    local patches = {
        E.Patch(session.rootId, removeFirst, removeLast, {}),
        E.InsertBlockAfterDocLine(session.texts, session.rootId, anchor, lines),
    }
    local ok = B.Commit(session, string.format("Moved '%s' to round %s.", entry.name, tostring(beat.rounds[toRound].number)), patches)
    if ok then
        local newBeat = B.CurrentBeat(session)
        local newRound = newBeat ~= nil and newBeat.rounds[toRound] or nil
        session.selected = nil
        for j, e in ipairs(newRound ~= nil and newRound.entries or {}) do
            if e.name == entry.name then
                session.selected = { kind = "entry", round = toRound, index = j }
            end
        end
    end
    return ok
end

--Make a new journal document under the map; it counts as pending until the
--server sends it back. Returns its id.
local function CreateDocument(session, name, text)
    local id = dmhub.GenerateGuid()
    local doc = MarkdownDocument.new{
        id = id,
        description = name,
        parentFolder = session.mapid,
        annotations = {},
    }
    doc:SetTextContent(text)
    doc:Upload()
    session.pending[id] = { name = name, doc = doc }
    session.names[id] = name
    session.texts[id] = text
    return id
end

local function DefaultObstacle(name)
    local block = { "## Obstacle: " .. name, "", "Describe what blocks the way.", "", "### Push through", "" }
    for _, l in ipairs(E.RollLines{ name = "Test", attr = "Might (Endurance, Climb)",
        tiers = { { text = "You lose 3 stamina" }, { text = "You lose 1 stamina" }, { text = "You get through unharmed" } } }) do
        block[#block + 1] = l
    end
    return block
end

--An option that enters a brand-new delve: the delve in its own
--sub-document (included at the end of the master, after every beat, so it
--never splits the montage), the option appended to the entry.
function B.AddDelveOption(session, entry)
    local name = UniqueDocName(session, "New Delve")
    local lines = { "# Delve: " .. name, "", "Chest: every 1-2 obstacles", "" }
    for _, l in ipairs(DefaultObstacle("A Dark Passage")) do lines[#lines + 1] = l end
    for _, l in ipairs({ "", "## Chest", "", "PC pries open a dusty chest.", "" }) do lines[#lines + 1] = l end
    for _, l in ipairs(E.TableLines{ name = "Treasure", dice = "1d6", rows = { { lo = 1, hi = 3, text = "You gain 1 Healing Potion" }, { lo = 4, hi = 6, text = "+1 hero token" } } }) do
        lines[#lines + 1] = l
    end
    for _, l in ipairs({ "", "## Continue", "", "PC peers deeper into the dark.", "", "## Leave", "", "PC turns back toward the light.", "", "## Forced Out", "", "Exhausted, PC staggers out." }) do
        lines[#lines + 1] = l
    end
    local id = CreateDocument(session, name, table.concat(lines, "\n") .. "\n")

    local rootLines = E.Split(session.texts[session.rootId]).lines
    local endLine = #rootLines
    while endLine > 0 and trim(rootLines[endLine]) == "" do
        endLine = endLine - 1
    end
    local patches = { E.InsertBlockAfterDocLine(session.texts, session.rootId, endLine, { E.IncludeLine(name) }) }
    local optionPatches, why = E.InsertAfterElement(session.parse, session.texts, entry.line, 2,
        { "### Explore " .. name, "", "Delve: " .. name })
    if optionPatches == nil then
        session.status = "Not added: " .. tostring(why)
        return false
    end
    for _, p in ipairs(optionPatches) do
        patches[#patches + 1] = p
    end
    local ok = B.Commit(session, string.format("Added the delve '%s'.", name), patches)
    if ok then
        session.undo[#session.undo].created = id
    end
    return ok
end

--A new obstacle at the end of a delve's obstacles.
function B.AddObstacle(session, delveKey)
    local delve = session.parse.delves[delveKey]
    if delve == nil then
        return false
    end
    local block = DefaultObstacle("New Obstacle")
    local last = delve.obstacles[#delve.obstacles]
    local patches, why
    if last ~= nil then
        patches, why = E.InsertAfterElement(session.parse, session.texts, last.line, 2, block)
    else
        patches, why = One(E.InsertBlockAfter(session.parse, session.texts, delve.line, block))
    end
    return B.Commit(session, "Added an obstacle.", patches, why)
end

--- UI building blocks ---------------------------------------------------------------

local STYLES = {
        { selectors = { "mbCard" }, width = "100%", height = "auto", flow = "vertical", vmargin = 3,
            hpad = 8, vpad = 6, borderBox = true, bgimage = "panels/square.png", bgcolor = "#ffffff10",
            borderWidth = 1, borderColor = "#ffffff30", cornerRadius = 4 },
        { selectors = { "mbCard", "hover" }, bgcolor = "#ffffff22" },
        { selectors = { "mbCard", "selected" }, borderColor = "#ffd27a", borderWidth = 2, bgcolor = "#ffd27a18" },
        { selectors = { "mbSection" }, width = "100%", height = "auto", flow = "vertical", vmargin = 6,
            pad = 10, borderBox = true, bgimage = "panels/square.png", bgcolor = "#00000040",
            borderWidth = 1, borderColor = "#ffffff20", cornerRadius = 4 },
        { selectors = { "mbHeading" }, fontSize = 18, bold = true, width = "100%", height = "auto", bmargin = 4 },
        { selectors = { "mbSub" }, fontSize = 13, color = "#b0b0b0", width = "100%", height = "auto" },
        { selectors = { "mbRule" }, fontSize = 13, color = RULE_COLOR, width = "100%", height = "auto" },
        { selectors = { "mbProblem" }, fontSize = 13, color = PROBLEM_COLOR, width = "100%", height = "auto" },
        { selectors = { "mbFieldLabel" }, fontSize = 13, bold = true, color = "#d8d8d8", width = "100%", height = "auto", tmargin = 6, bmargin = 2 },
}

local function Label(text, classes, extra)
    local args = {
        classes = classes or { "mbSub" },
        text = text,
        textWrap = true,
        width = "100%",
        height = "auto",
    }
    for k, v in pairs(extra or {}) do
        args[k] = v
    end
    return gui.Label(args)
end

--A text box that commits on change. opts = { multiline, placeholder, width, height, fontSize }
local function TextBox(text, onCommit, opts)
    opts = opts or {}
    return gui.Input{
        classes = { "sizeS", "bordered" },
        width = opts.width or "100%",
        height = opts.multiline and "auto" or (opts.height or 26),
        minHeight = opts.multiline and (opts.minHeight or 44) or nil,
        maxHeight = opts.multiline and (opts.maxHeight or 260) or nil,
        multiline = opts.multiline == true,
        textAlignment = opts.multiline and "topleft" or "left",
        characterLimit = 20000,
        placeholderText = opts.placeholder or "",
        text = text or "",
        vmargin = 2,
        change = function(element)
            if element.text ~= (text or "") then
                onCommit(element.text)
            end
        end,
    }
end

--Clauses the grammar recognises, lit green, as one line of preview.
local function RulesPreview(text)
    if trim(text or "") == "" then
        return nil
    end
    local marked = EncounterScript.MarkupRules(text, "<color=" .. RULE_COLOR .. ">", "</color>")
    local effects = EncounterScript.ParseEffects(EncounterScript.VisibleText(text))
    local described = {}
    for _, effect in ipairs(effects) do
        if EncounterScript.EffectIsMechanical(effect) then
            local d = nil
            pcall(function() d = EncounterScript.DescribeEffect(effect) end)
            if d ~= nil and d ~= "" then
                described[#described + 1] = d
            end
        end
    end
    local summary = cond(#described > 0, "Does: " .. table.concat(described, "; "), "No rules recognised: text only.")
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        Label(marked, { "mbSub" }, { markdown = false }),
        Label(summary, { cond(#described > 0, "mbRule", "mbSub") }),
    }
end

local function SmallButton(text, onClick, extraClasses)
    local classes = { "sizeXs" }
    for _, c in ipairs(extraClasses or {}) do
        classes[#classes + 1] = c
    end
    return gui.Button{
        classes = classes,
        width = "auto",
        minWidth = 60,
        hpad = 8,
        borderBox = true,
        height = 24,
        text = text,
        rmargin = 4,
        click = function(element)
            onClick(element)
        end,
    }
end

--A button that needs a second click to act.
local function ConfirmButton(text, onConfirm)
    local armed = false
    local button
    button = gui.Button{
        classes = { "sizeXs" },
        width = "auto",
        minWidth = 60,
        hpad = 8,
        borderBox = true,
        height = 24,
        text = text,
        rmargin = 4,
        click = function(element)
            if armed then
                onConfirm()
                return
            end
            armed = true
            element.text = "Click again to confirm"
            dmhub.Schedule(3, function()
                if element.valid then
                    armed = false
                    element.text = text
                end
            end)
        end,
    }
    return button
end

--A horizontal row. A row wider than its content spreads the children over
--it, so a row of buttons passes { fit = true } to hug them on the left.
local function Row(children, extra)
    local args = { width = "100%", height = "auto", flow = "horizontal", children = children, vmargin = 2 }
    if extra ~= nil and extra.fit then
        args.width = "auto"
        args.halign = "left"
        extra = DeepCopy(extra)
        extra.fit = nil
    end
    for k, v in pairs(extra or {}) do
        args[k] = v
    end
    return gui.Panel(args)
end

--- the window -----------------------------------------------------------------------

function B.CreateWindow(session, close)
    local boardPanel, editorPanel, boardBody, editorBody, statusLabel, titleLabel, beatDropdown
    local Refresh

    --Run an edit and redraw. fn() returns what to show in the status line,
    --or the result of B.Commit.
    local function Do(fn)
        local ok, err = pcall(fn)
        if not ok then
            session.status = "Error: " .. tostring(err)
        end
        Refresh()
    end

    local function Commit(what, patches, why)
        Do(function() B.Commit(session, what, patches, why) end)
    end

    --- scene lines ---
    --A scene is one step per line. Each row edits its own line (keeping the
    --line's indentation); rows can be added below and removed. `steps` are
    --the parser's { text, line } list; `anchor` is the expanded line new
    --steps go after when the list is empty.
    local SCENE_TEMPLATES = {
        { id = "narrate", text = "Narration", lines = { "PC looks around." } },
        { id = "pcsay", text = "PC says", lines = { "PC: Hello there!" } },
        { id = "enter", text = "Character enters", lines = { "Stranger (Bandit) enters" } },
        { id = "say", text = "Character says", lines = { "Stranger: Who goes there?" } },
        { id = "foreign", text = "Character says (in a language)", lines = { "Stranger: (in Caelian) Who goes there?" } },
        { id = "emote", text = "Emote", lines = { "Stranger is alert" } },
        { id = "exit", text = "Character exits", lines = { "Stranger exits" } },
        { id = "ifspeaks", text = "Branch: if PC speaks...", lines = { "if PC speaks Caelian then", "    PC: I understand you.", "else", "    PC: What did they say?", "end" } },
        { id = "iftier", text = "Branch: by tier", lines = { "if tier1 then", "    PC: That went badly.", "elseif tier2 then", "    PC: Not bad.", "else", "    PC: Perfect!", "end" } },
    }

    local function StepKind(text)
        local t = lower(trim(text))
        if string.match(t, "^if%s") or string.match(t, "^elseif%s") or t == "else" or t == "end" then
            return "Branch", "#c9a4ff"
        elseif string.match(t, "%s+enters$") or string.match(t, "%s+appears$") or string.match(t, "%s+arrives$") or string.match(t, "%)%s+enters$") then
            return "Enters", "#9fd0ff"
        elseif string.match(t, "%s+exits$") or string.match(t, "%s+leaves$") or string.match(t, "%s+departs$") then
            return "Exits", "#9fd0ff"
        elseif string.match(t, "%s+is%s+alert$") or string.match(t, "%s+is%s+alarmed$") or string.match(t, "%s+is%s+scared$") then
            return "Emote", "#e8c27a"
        elseif string.match(trim(text), "^[^:]+:%s") and not string.match(t, "^[%a]+:%s*$") then
            return "Says", "#ffffff"
        end
        return "Narration", "#b0b0b0"
    end

    local function SceneEditor(title, steps, anchor)
        local parse = session.parse
        ---@type Panel[]
        local children = { Label(title, { "mbFieldLabel" }) }
        local depth = 0
        for _, step in ipairs(steps or {}) do
            local s = step
            local kind, color = StepKind(s.text)
            local t = lower(trim(s.text))
            if t == "end" or t == "else" or string.match(t, "^elseif%s") then
                depth = math.max(0, depth - 1)
            end
            local indent = depth * 20
            children[#children + 1] = Row({
                gui.Label{ fontSize = 11, bold = true, color = color, width = 74, height = "auto", valign = "center", text = string.upper(kind) },
                gui.Panel{ width = indent, height = 1 },
                TextBox(s.text, function(text)
                    --keep the line's own indentation.
                    local docid, at = E.Source(parse, s.line)
                    local raw = E.Split(session.texts[docid] or "").lines[at] or ""
                    local lead = string.match(raw, "^(%s*)") or ""
                    Commit("Edited a scene line.", E.SetLine(parse, s.line, lead .. E.LineText(text)))
                end, { width = string.format("100%%-%d", 150 + indent), height = 24 }),
                gui.Button{ classes = { "sizeXs" }, width = 26, height = 24, lmargin = 4, text = "+",
                    hover = gui.Tooltip("Add a narration line below this one"),
                    click = function()
                        local docid, at = E.Source(parse, s.line)
                        local raw = E.Split(session.texts[docid] or "").lines[at] or ""
                        local lead = string.match(raw, "^(%s*)") or ""
                        Commit("Added a scene line.", One(E.PatchAfter(parse, s.line, { lead .. "PC looks around." })))
                    end },
                gui.Button{ classes = { "sizeXs" }, width = 26, height = 24, lmargin = 2, text = "x",
                    hover = gui.Tooltip("Remove this line"),
                    click = function()
                        Commit("Removed a scene line.", E.DeleteLine(parse, s.line))
                    end },
            }, { vmargin = 1 })
            if string.match(t, "^if%s") or t == "else" or string.match(t, "^elseif%s") then
                depth = depth + 1
            end
        end
        if #(steps or {}) == 0 then
            children[#children + 1] = Label("(no lines yet)", { "mbSub" })
        end
        local options = { { id = "", text = "+ Add a step..." } }
        for _, tpl in ipairs(SCENE_TEMPLATES) do
            options[#options + 1] = { id = tpl.id, text = tpl.text }
        end
        children[#children + 1] = gui.Dropdown{
            classes = { "sizeXs" },
            width = 240,
            height = 24,
            tmargin = 2,
            options = options,
            idChosen = "",
            change = function(element)
                ---@cast element Dropdown
                for _, tpl in ipairs(SCENE_TEMPLATES) do
                    if tpl.id == element.idChosen then
                        local last = steps ~= nil and steps[#steps] ~= nil and steps[#steps].line or anchor
                        if last == nil then
                            session.status = "Nowhere to put the line."
                            Refresh()
                            return
                        end
                        Commit("Added a scene step.", One(E.PatchAfter(parse, last, tpl.lines)))
                    end
                end
            end,
        }
        children[#children + 1] = Label("PC is the hero at the entry. 'Name (Monster) enters' brings on a character with that bestiary portrait; '(in Caelian)' garbles a line for heroes who do not speak it; branches test 'PC speaks X', 'PC is X', 'PC can X', 'PC chose <option>', tier1-3, crit.", { "mbSub" })
        return gui.Panel{ classes = { "mbSection" }, children = children }
    end

    --- dice tables ---
    local function TableEditor(t, title)
        local parse = session.parse
        local children = {}
        children[#children + 1] = Row({
            gui.Label{ classes = { "mbFieldLabel" }, width = "auto", height = "auto", valign = "center", rmargin = 8, text = title or "Dice table" },
            TextBox(t.name, function(text)
                Commit("Renamed a dice table.", E.SetLine(parse, t.line, string.format("|%s: %s", trim((string.gsub(E.LineText(text), ":", ""))), t.dice)))
            end, { width = 220, height = 24 }),
            TextBox(t.dice, function(text)
                Commit("Changed a table's dice.", E.SetLine(parse, t.line, string.format("|%s: %s", t.name, E.LineText(text))))
            end, { width = 70, height = 24 }),
        }, { fit = true })
        for _, row in ipairs(t.rows or {}) do
            local r = row
            local range = cond(r.lo == r.hi, tostring(r.lo), string.format("%d-%d", r.lo, r.hi))
            children[#children + 1] = Row({
                TextBox(range, function(text)
                    Commit("Edited a table row.", E.SetLine(parse, r.line, string.format("|%s: %s", trim(text), r.text)))
                end, { width = 60, height = 24 }),
                gui.Panel{
                    width = "100%-100",
                    height = "auto",
                    flow = "vertical",
                    TextBox(r.text, function(text)
                        Commit("Edited a table row.", E.SetLine(parse, r.line, string.format("|%s: %s", range, E.LineText(text))))
                    end, { height = 24 }),
                    RulesPreview(r.text),
                },
                gui.Button{ classes = { "sizeXs" }, width = 26, height = 24, lmargin = 4, text = "x",
                    click = function()
                        Commit("Removed a table row.", E.DeleteLine(parse, r.line))
                    end },
            })
        end
        children[#children + 1] = Row({
            SmallButton("+ Row", function()
                local after = t.lastLine or t.line
                local hi = 0
                for _, r in ipairs(t.rows or {}) do hi = math.max(hi, r.hi or 0) end
                Commit("Added a table row.", One(E.PatchAfter(parse, after, { string.format("|%d: +1 hero token", hi + 1) })))
            end),
        }, { fit = true })
        return gui.Panel{ classes = { "mbSection" }, children = children }
    end

    --- the rules of an option or knack version: its test, or its no-roll rules, and riders ---
    local function RulesEditor(entry, holder, children)
        local parse = session.parse
        local roll = holder.roll
        if roll ~= nil then
            local chars, skills = B.SplitAttr(roll.attr)
            local function WriteHeader(name, newChars, newSkills)
                Commit("Edited a test.", E.SetRollHeader(parse, roll, name, E.AttrText(newChars, newSkills)))
            end
            children[#children + 1] = Label("Test", { "mbFieldLabel" })
            children[#children + 1] = Row({
                gui.Label{ classes = { "mbSub" }, width = 60, height = "auto", valign = "center", text = "Name" },
                TextBox(roll.name, function(text) WriteHeader(text, chars, skills) end, { width = 220 }),
            }, { fit = true })
            local charChecks = {}
            for _, c in ipairs(CHARACTERISTICS) do
                local has = false
                for _, x in ipairs(chars) do
                    if x == c then has = true end
                end
                local characteristic = c
                charChecks[#charChecks + 1] = gui.Check{
                    classes = { "sizeXs" },
                    fontSize = 14,
                    width = 100,
                    height = 24,
                    text = characteristic,
                    value = has,
                    change = function(element)
                        local list = {}
                        for _, x in ipairs(CHARACTERISTICS) do
                            local keep = false
                            for _, y in ipairs(chars) do
                                if y == x then keep = true end
                            end
                            if x == characteristic then keep = element.value == true end
                            if keep then list[#list + 1] = x end
                        end
                        if #list == 0 then
                            session.status = "A test needs at least one characteristic."
                            Refresh()
                            return
                        end
                        WriteHeader(roll.name, list, skills)
                    end,
                }
            end
            children[#children + 1] = Row(charChecks, { fit = true })

            --skills: chips with an x, and a dropdown to add one.
            local skillChildren = { gui.Label{ classes = { "mbSub" }, width = 60, height = "auto", valign = "center", text = "Skills" } }
            local known = {}
            for _, s in ipairs(B.SkillOptions()) do
                known[lower(s)] = true
            end
            for si, s in ipairs(skills) do
                local index = si
                skillChildren[#skillChildren + 1] = gui.Button{
                    classes = { "sizeXs" },
                    width = "auto",
                    hpad = 8,
                    borderBox = true,
                    height = 24,
                    rmargin = 4,
                    text = s .. "  x",
                    color = cond(known[lower(s)], nil, PROBLEM_COLOR),
                    hover = gui.Tooltip(cond(known[lower(s)], "Remove this skill", "'" .. s .. "' is not a skill name: it adds nothing to the roll. Click to remove.")),
                    click = function()
                        local list = {}
                        for k, x in ipairs(skills) do
                            if k ~= index then list[#list + 1] = x end
                        end
                        WriteHeader(roll.name, chars, list)
                    end,
                }
            end
            local addOptions = { { id = "", text = "+ Add skill" } }
            for _, s in ipairs(B.SkillOptions()) do
                addOptions[#addOptions + 1] = { id = s, text = s }
            end
            skillChildren[#skillChildren + 1] = gui.Dropdown{
                classes = { "sizeXs" },
                width = 150,
                height = 24,
                options = addOptions,
                idChosen = "",
                hasSearch = true,
                change = function(element)
                    ---@cast element Dropdown
                    local chosen = element.idChosen
                    if type(chosen) == "string" and chosen ~= "" then
                        local list = {}
                        for _, x in ipairs(skills) do list[#list + 1] = x end
                        list[#list + 1] = chosen
                        WriteHeader(roll.name, chars, list)
                    end
                end,
            }
            children[#children + 1] = Row(skillChildren, { fit = true })
            if #skills < 2 then
                children[#children + 1] = Label("List two or more skills if companions should be able to assist with this test.", { "mbSub" })
            end

            --tiers.
            children[#children + 1] = Label("Outcomes: the teaser is what players see until that tier lands (optional)", { "mbFieldLabel" })
            for t = 1, 3 do
                local tier = t
                children[#children + 1] = Row({
                    gui.Label{ classes = { "mbSub" }, width = 90, height = "auto", valign = "top", tmargin = 4, text = TIER_RANGES[t] },
                    gui.Panel{
                        width = "100%-96",
                        height = "auto",
                        flow = "vertical",
                        TextBox(roll.teasers[t], function(text)
                            Commit("Edited a teaser.", E.SetTier(parse, roll, tier, text, roll.tiers[tier]))
                        end, { placeholder = "Teaser (optional)", height = 24 }),
                        TextBox(roll.tiers[t], function(text)
                            Commit("Edited an outcome.", E.SetTier(parse, roll, tier, roll.teasers[tier], text))
                        end, { multiline = true, minHeight = 26, placeholder = "What happens: e.g. You gain 1 Healing Potion. +1 hero token" }),
                        RulesPreview(roll.tiers[t]),
                    },
                })
            end
            --the critical: automatic (tier 3 + a hero token) unless one is written.
            local critChildren = {
                gui.Check{
                    classes = { "sizeXs" },
                    width = 400,
                    height = 24,
                    text = "Automatic: tier 3 plus an additional hero token",
                    value = roll.critAuto == true,
                    change = function(element)
                        if element.value then
                            Commit("Critical set to automatic.", E.ClearCritical(parse, roll))
                        else
                            Commit("Wrote a critical.", E.SetTier(parse, roll, 4, nil, roll.tiers[4]))
                        end
                    end,
                },
            }
            if not roll.critAuto then
                critChildren[#critChildren + 1] = TextBox(roll.tiers[4], function(text)
                    Commit("Edited the critical.", E.SetTier(parse, roll, 4, roll.teasers[4], text))
                end, { multiline = true, minHeight = 26 })
                critChildren[#critChildren + 1] = RulesPreview(roll.tiers[4])
            end
            children[#children + 1] = Row({
                gui.Label{ classes = { "mbSub" }, width = 90, height = "auto", valign = "top", tmargin = 4, text = "Critical" },
                gui.Panel{
                    width = "100%-96",
                    height = "auto",
                    flow = "vertical",
                    children = critChildren,
                },
            })
        elseif holder.free ~= nil then
            children[#children + 1] = Label("Rules (one per line; they apply at once, no roll)", { "mbFieldLabel" })
            local ruleLines = {}
            for _, l in ipairs(holder.free.lines or {}) do
                local docid, at = E.Source(parse, l)
                ruleLines[#ruleLines + 1] = (string.gsub(E.Split(session.texts[docid] or "").lines[at] or "", "^%s*|", ""))
            end
            children[#children + 1] = TextBox(table.concat(ruleLines, "\n"), function(text)
                local block = {}
                for _, l in ipairs(E.ProseLines(text)) do
                    if l ~= "" then
                        block[#block + 1] = "|" .. E.LineText(l)
                    end
                end
                for _, r in ipairs(holder.riders or {}) do
                    block[#block + 1] = E.RiderLine(r.effect, r.round, r.text)
                end
                if #block == 0 then
                    session.status = "An option with no roll needs at least one rule."
                    Refresh()
                    return
                end
                Commit("Edited the rules.", E.SetRules(parse, session.texts, holder, block))
            end, { multiline = true })
            children[#children + 1] = RulesPreview(holder.free.text)
        end

        --riders (on the roll, or on the option itself).
        local riders = {}
        if roll ~= nil then
            for _, r in ipairs(roll.riders or {}) do riders[#riders + 1] = r end
        end
        for _, r in ipairs(holder.riders or {}) do riders[#riders + 1] = r end
        if roll ~= nil or holder.free ~= nil then
            children[#children + 1] = Label("Knacks: edges, banes and secret (Allow) requirements", { "mbFieldLabel" })
            local effectOptions = {}
            for _, eff in ipairs(E.RIDER_EFFECTS) do
                effectOptions[#effectOptions + 1] = { id = eff, text = E.RiderWord(eff) }
            end
            local roundOptions = { { id = "any", text = "Any round" } }
            local beat = B.CurrentBeat(session)
            for r = 1, math.max(1, beat ~= nil and #beat.rounds or 1) do
                roundOptions[#roundOptions + 1] = { id = tostring(r), text = "Round " .. r }
            end
            for _, rider in ipairs(riders) do
                local r = rider
                local problems = {}
                pcall(function() problems = EncounterScript.RequirementProblems(r.requirement) end)
                children[#children + 1] = Row({
                    gui.Dropdown{
                        classes = { "sizeXs" },
                        width = 120,
                        height = 24,
                        options = effectOptions,
                        idChosen = r.effect,
                        change = function(element)
                            ---@cast element Dropdown
                            Commit("Edited a knack.", E.SetRider(parse, r, element.idChosen, r.round, r.text))
                        end,
                    },
                    gui.Dropdown{
                        classes = { "sizeXs" },
                        width = 100,
                        height = 24,
                        lmargin = 4,
                        options = roundOptions,
                        idChosen = r.round ~= nil and tostring(r.round) or "any",
                        change = function(element)
                            ---@cast element Dropdown
                            local round = tonumber(element.idChosen)
                            Commit("Edited a knack.", E.SetRider(parse, r, r.effect, round, r.text))
                        end,
                    },
                    TextBox(r.text, function(text)
                        Commit("Edited a knack.", E.SetRider(parse, r, r.effect, r.round, text))
                    end, { width = "100%-300" }),
                    SmallButton("Remove", function()
                        Commit("Removed a knack.", E.RemoveRider(parse, r))
                    end),
                })
                for _, p in ipairs(problems or {}) do
                    children[#children + 1] = Label(p, { "mbProblem" })
                end
            end
            local addRow = {}
            if roll ~= nil then
                addRow[#addRow + 1] = SmallButton("+ Edge", function()
                    Commit("Added a knack.", E.AddRider(parse, session.texts, holder, "edge", nil, "you can climb"))
                end)
                addRow[#addRow + 1] = SmallButton("+ Bane", function()
                    Commit("Added a knack.", E.AddRider(parse, session.texts, holder, "bane", nil, "you have cold weakness"))
                end)
            end
            addRow[#addRow + 1] = SmallButton("+ Secret (Allow)", function()
                Commit("Added a knack.", E.AddRider(parse, session.texts, holder, "allow", nil, "you are a Dwarf"))
            end)
            children[#children + 1] = Row(addRow, { fit = true })
            children[#children + 1] = Label("Requirements read as intent: 'you can teleport', 'you speak Zaliac', 'you are a Dwarf', 'you are skilled in Track', 'you have the Lucky Dog perk', 'your Wealth is 2 or higher'... (KNACKS_REFERENCE.md).", { "mbSub" })
        end

        --switch between a test and no roll.
        local switch = {}
        if roll ~= nil then
            switch[#switch + 1] = SmallButton("Make it no-roll", function()
                local block = { "|" .. E.LineText(roll.tiers[2]) }
                for _, r in ipairs(riders) do
                    if r.effect == "allow" then
                        block[#block + 1] = E.RiderLine(r.effect, r.round, r.text)
                    end
                end
                Commit("Changed to no roll.", E.SetRules(parse, session.texts, holder, block))
            end)
        elseif holder.free ~= nil or holder.delve == nil then
            switch[#switch + 1] = SmallButton("Make it a test", function()
                local block = DefaultRoll(entry.kind)
                for _, r in ipairs(riders) do
                    block[#block + 1] = E.RiderLine(r.effect, r.round, r.text)
                end
                Commit("Changed to a test.", E.SetRules(parse, session.texts, holder, block))
            end)
        end
        return switch
    end

    --An element's text editor: the element as written, saved back whole.
    local function TextEditorPanel(line, level, note)
        local parse = session.parse
        local text = table.concat(E.ElementLines(parse, session.texts, line, level) or {}, "\n")
        local input = TextBox(text, function() end, { multiline = true, maxHeight = 600 })
        return gui.Panel{
            classes = { "collapsed" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            Label(note, { "mbSub" }),
            input,
            Row({
                SmallButton("Save text", function()
                    Commit("Edited as text.", E.ReplaceElement(parse, session.texts, line, level, input.text))
                end),
            }, { fit = true }),
        }
    end

    --- the editor for one knack version ---
    local function KnackEditor(entry, o, k)
        local parse = session.parse
        local children = {}
        children[#children + 1] = Row({
            gui.Label{ classes = { "mbHeading" }, color = "#d9b3ff", width = "auto", height = "auto", valign = "center", rmargin = 8, text = "KNACK: If" },
            TextBox(k.requirementText, function(text)
                Commit("Edited a knack version.", E.SetLine(parse, k.line, E.KnackHeadingLine(text)))
            end, { width = 420 }),
        }, { fit = true })
        children[#children + 1] = Label("A hero who meets this takes this version of the option instead: no roll (the knack makes the problem moot) or a better test.", { "mbSub" })
        local problems = {}
        pcall(function() problems = EncounterScript.RequirementProblems(k.requirement) end)
        for _, p in ipairs(problems or {}) do
            children[#children + 1] = Label(p, { "mbProblem" })
        end
        if entry.scripted then
            children[#children + 1] = SceneEditor("Before (after the option's own lines)", k.preLines, k.line)
        end
        local switch = RulesEditor(entry, k, children)
        if entry.scripted then
            local anchor = B.RulesEnd(k)
            if anchor ~= nil then
                children[#children + 1] = SceneEditor("After the outcome (otherwise the option's own)", k.postLines, anchor)
            end
        end
        local tools = {}
        for _, b in ipairs(switch) do tools[#tools + 1] = b end
        tools[#tools + 1] = ConfirmButton("Delete knack version", function()
            Commit("Deleted a knack version.", E.DeleteElement(parse, session.texts, k.line, 4))
        end)
        children[#children + 1] = Row(tools, { fit = true, tmargin = 6 })
        return gui.Panel{ classes = { "mbSection" }, borderColor = "#d9b3ff60", children = children }
    end

    --- the editor for one option ---
    local function OptionEditor(entry, o, optionIndex)
        local parse = session.parse
        local children = {}
        local kindText
        if o.delve ~= nil then
            kindText = "Enters the delve '" .. o.delve .. "' (edit it from the board)"
        elseif o.roll ~= nil then
            kindText = "Test"
        elseif o.free ~= nil then
            kindText = "No roll: its rules apply at once"
        else
            kindText = "No rules yet"
        end
        local secret = EncounterScript.OptionIsSecret(o)

        children[#children + 1] = Row({
            gui.Label{ classes = { "mbHeading" }, width = 30, text = tostring(optionIndex) .. "." },
            TextBox(o.name, function(text)
                Commit("Renamed an option.", E.SetLine(parse, o.line, E.OptionHeadingLine(text)))
            end, { width = 380 }),
            gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", lmargin = 8,
                text = kindText .. cond(secret, "  (SECRET: only heroes who meet an Allow line see it)", "") },
        }, { fit = true })

        if entry.scripted then
            children[#children + 1] = SceneEditor("Scene when chosen (before the roll)", o.preLines, o.line)
        else
            children[#children + 1] = Label("What the option says (optional)", { "mbFieldLabel" })
            children[#children + 1] = TextBox(o.text, function(text)
                Commit("Edited an option's text.", E.SetProse(parse, session.texts, o.textLines, o.line, text))
            end, { multiline = true, placeholder = "Shown with the option." })
        end

        local switch = {}
        if o.delve == nil then
            switch = RulesEditor(entry, o, children)
        end
        if entry.scripted and o.delve == nil then
            local anchor = B.RulesEnd(o)
            if anchor ~= nil then
                children[#children + 1] = SceneEditor("Outcome scene (after the roll; effects apply once it has been read)", o.postLines, anchor)
            end
        end

        for _, k in ipairs(o.knacks or {}) do
            children[#children + 1] = KnackEditor(entry, o, k)
        end

        --option tools.
        local textEditor = TextEditorPanel(o.line, 3, "The option as written. Anything the forms above do not cover can be edited here.")
        local toolRow = {
            SmallButton("Edit as text", function()
                textEditor:SetClass("collapsed", not textEditor:HasClass("collapsed"))
            end),
        }
        for _, b in ipairs(switch) do toolRow[#toolRow + 1] = b end
        if o.delve == nil then
            toolRow[#toolRow + 1] = SmallButton("+ Knack version (no roll)", function()
                Commit("Added a knack version.", E.InsertAfterElement(parse, session.texts, o.line, 3,
                    { E.KnackHeadingLine("you can teleport"), "", "|The problem is solved in a blink. +1 hero token" }))
            end)
            toolRow[#toolRow + 1] = SmallButton("+ Knack version (own test)", function()
                local block = { E.KnackHeadingLine("you can fly"), "" }
                for _, l in ipairs(DefaultRoll(entry.kind)) do block[#block + 1] = l end
                Commit("Added a knack version.", E.InsertAfterElement(parse, session.texts, o.line, 3, block))
            end)
        end
        toolRow[#toolRow + 1] = ConfirmButton("Delete option", function()
            Commit(string.format("Deleted option '%s'.", o.name), E.DeleteElement(parse, session.texts, o.line, 3))
        end)
        children[#children + 1] = Row(toolRow, { fit = true, tmargin = 6 })
        children[#children + 1] = textEditor

        return gui.Panel{
            classes = { "mbSection" },
            children = children,
        }
    end

    --- the editor for one entry ---
    local function EntryEditor(entry)
        local parse = session.parse
        local children = {}
        local isObstacle = entry.kind == "obstacle"
        local isSection = entry.kind == "delvesection"
        local color = cond(entry.kind == "threat", THREAT_COLOR, cond(isObstacle or isSection, OBSTACLE_COLOR, OPPORTUNITY_COLOR))

        if isSection then
            children[#children + 1] = Label(string.upper("Delve: " .. tostring(entry.delve) .. " -- " .. entry.name), { "mbHeading" }, { color = color })
            children[#children + 1] = SceneEditor("Scene", entry.sceneLines, entry.line)
            if entry.table ~= nil then
                children[#children + 1] = TableEditor(entry.table, "Treasure table")
            elseif entry.section == "chest" then
                children[#children + 1] = Row({
                    SmallButton("+ Treasure table", function()
                        Commit("Added a treasure table.", E.InsertAfterElement(parse, session.texts, entry.line, 2,
                            E.TableLines{ name = "Treasure", dice = "1d6", rows = { { lo = 1, hi = 3, text = "You gain 1 Healing Potion" }, { lo = 4, hi = 6, text = "+1 hero token" } } }))
                    end),
                }, { fit = true })
            end
            local textEditor = TextEditorPanel(entry.line, 2, "The section as written.")
            children[#children + 1] = Row({
                SmallButton("Edit as text", function() textEditor:SetClass("collapsed", not textEditor:HasClass("collapsed")) end),
                ConfirmButton("Delete section", function()
                    session.selected = nil
                    Commit("Deleted a delve section.", E.DeleteElement(parse, session.texts, entry.line, 2))
                end),
            }, { fit = true, tmargin = 8 })
            children[#children + 1] = textEditor
            return children
        end

        children[#children + 1] = Row({
            gui.Label{ classes = { "mbHeading" }, width = "auto", height = "auto", valign = "center", rmargin = 8, color = color,
                text = string.upper(cond(isObstacle, "Obstacle", entry.kind)) },
            TextBox(entry.name, function(text)
                Do(function() B.RenameEntry(session, entry, text) end)
            end, { width = 320, height = 28 }),
        }, { fit = true })
        children[#children + 1] = Label(string.format("In the journal document '%s'.", B.SourceName(session, entry.line)), { "mbSub" })

        if not isObstacle then
            local tagRow = {
                gui.Dropdown{
                    classes = { "sizeXs" },
                    width = 130,
                    height = 24,
                    options = { { id = "opportunity", text = "Opportunity" }, { id = "threat", text = "Threat" } },
                    idChosen = entry.kind,
                    change = function(element)
                        ---@cast element Dropdown
                        Commit("Changed the entry's kind.", E.SetEntryHeading(parse, entry, { kind = element.idChosen }))
                    end,
                },
            }
            local tagHelp = {
                required = "Never removed by the party-size trim.",
                locked = "Off the board until an 'unlock <name>' outcome lands.",
                temporary = "Gone at the end of the round it appears in.",
            }
            for _, tag in ipairs({ "required", "locked", "temporary" }) do
                local key = tag
                tagRow[#tagRow + 1] = gui.Check{
                    classes = { "sizeXs" },
                    fontSize = 14,
                    width = 120,
                    height = 24,
                    lmargin = 8,
                    text = string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2),
                    value = entry[key] == true,
                    hover = gui.Tooltip(tagHelp[key]),
                    change = function(element)
                        Commit("Changed the entry's tags.", E.SetEntryHeading(parse, entry, { [key] = element.value == true }))
                    end,
                }
            end
            children[#children + 1] = Row(tagRow, { fit = true, tmargin = 4 })
        end

        children[#children + 1] = Label("Card text: what the party reads on the board", { "mbFieldLabel" })
        children[#children + 1] = TextBox(entry.description, function(text)
            Commit("Edited the card text.", E.SetDescription(parse, session.texts, entry, text))
        end, { multiline = true, placeholder = "A cottage sits off the path, smoke curling from its chimney." })

        children[#children + 1] = Label("Approach text (optional 'Options:' line, shown when the hero steps up)", { "mbFieldLabel" })
        children[#children + 1] = TextBox(entry.approach, function(text)
            text = E.LineText(text)
            local block = cond(text == "", {}, { "Options: " .. text })
            if entry.approachLines ~= nil then
                local span = entry.approachLines
                Commit("Edited the approach text.", One(E.PatchExpanded(parse, span[1][1], span[#span][2], block)))
            elseif #block > 0 then
                local after = entry.line
                if entry.descriptionLines ~= nil then
                    after = entry.descriptionLines[#entry.descriptionLines][2]
                end
                Commit("Added approach text.", One(E.InsertBlockAfter(parse, session.texts, after, block)))
            end
        end, { placeholder = "Approaching the cottage, you see a witch within..." })

        if entry.kind == "threat" then
            children[#children + 1] = Label("Consequence: what happens at the end if the threat is never vanquished", { "mbFieldLabel" })
            children[#children + 1] = TextBox(entry.consequence ~= nil and entry.consequence.text or "", function(text)
                Commit("Edited the consequence.", E.SetConsequence(parse, session.texts, entry, text))
            end, { placeholder = "You begin the encounter surprised" })
            if entry.consequence ~= nil then
                children[#children + 1] = RulesPreview(entry.consequence.text)
            end
        end

        if entry.scripted then
            children[#children + 1] = SceneEditor("Scene: plays when a hero approaches", entry.sceneLines, entry.sceneSepLine)
        else
            children[#children + 1] = Row({
                SmallButton("+ Add a scene", function()
                    --"---" ends the card text; the scene follows it, above the first option.
                    local after = entry.line
                    if entry.consequence ~= nil and entry.consequence.lines ~= nil then
                        after = math.max(after, entry.consequence.lines[2])
                    end
                    if entry.approachLines ~= nil then
                        after = math.max(after, entry.approachLines[#entry.approachLines][2])
                    end
                    if entry.descriptionLines ~= nil then
                        after = math.max(after, entry.descriptionLines[#entry.descriptionLines][2])
                    end
                    Commit("Added a scene.", One(E.InsertBlockAfter(parse, session.texts, after, { "---", "", "PC approaches." })))
                end),
            }, { fit = true })
            children[#children + 1] = Label("A scene plays the approach as dialogue with portraits. With one, each option's own lines become its scenes too.", { "mbSub" })
        end

        for _, t in pairs(entry.tables or {}) do
            children[#children + 1] = TableEditor(t, "Dice table")
        end
        children[#children + 1] = Row({
            SmallButton("+ Dice table", function()
                local after = entry.line
                if entry.descriptionLines ~= nil then
                    after = entry.descriptionLines[#entry.descriptionLines][2]
                end
                Commit("Added a dice table.", One(E.InsertBlockAfter(parse, session.texts, after,
                    E.TableLines{ name = "Wares", dice = "1d6", rows = { { lo = 1, hi = 3, text = "You gain 1 Healing Potion" }, { lo = 4, hi = 6, text = "+1 hero token" } } })))
            end),
        }, { fit = true })
        children[#children + 1] = Label("An outcome rolls an entry's table with 'roll on <table name>' (or 'roll twice on ...').", { "mbSub" })

        children[#children + 1] = Label(string.format("Options (%d)", #entry.options), { "mbHeading" }, { tmargin = 10 })
        for i, o in ipairs(entry.options) do
            children[#children + 1] = OptionEditor(entry, o, i)
        end
        children[#children + 1] = Row({
            SmallButton("+ Option with a test", function()
                Commit("Added an option.", E.InsertAfterElement(parse, session.texts, entry.line, 2,
                    E.OptionBlock("New option", "", DefaultRoll(entry.kind))))
            end),
            SmallButton("+ Option with no roll", function()
                Commit("Added an option.", E.InsertAfterElement(parse, session.texts, entry.line, 2,
                    E.OptionBlock("New option", "", { "|+1 hero token" })))
            end),
            SmallButton("+ Option that enters a delve", function()
                Do(function() B.AddDelveOption(session, entry) end)
            end),
        }, { fit = true })

        --problems in this entry.
        local warnings, textOnly = {}, {}
        for _, w in ipairs(B.WarningsIn(session, entry.line, 2)) do
            if w.textOnly then
                textOnly[#textOnly + 1] = w
            else
                warnings[#warnings + 1] = w
            end
        end
        if #warnings > 0 then
            children[#children + 1] = Label(string.format("Problems (%d)", #warnings), { "mbHeading" }, { tmargin = 10, color = PROBLEM_COLOR })
            for _, w in ipairs(warnings) do
                children[#children + 1] = Label(w.message, { "mbProblem" })
            end
        end
        if #textOnly > 0 then
            local quoted = {}
            for _, w in ipairs(textOnly) do
                quoted[#quoted + 1] = string.match(w.message, "'(.-)'") or w.message
            end
            children[#children + 1] = Label(string.format("Text only, no rule matched (%d): usually flavour; check for a typo'd rule. %s",
                #textOnly, table.concat(quoted, " / ")), { "mbSub" }, { tmargin = 8 })
        end

        --entry tools.
        local textEditor = TextEditorPanel(entry.line, 2, "The entry as written in its document. Anything the forms do not cover can be edited here.")
        local tools = {
            SmallButton("Edit entry as text", function()
                textEditor:SetClass("collapsed", not textEditor:HasClass("collapsed"))
            end),
            SmallButton("Open in journal", function()
                local docid = E.Source(parse, entry.line)
                local doc = DocsTable()[docid]
                close()
                if doc ~= nil then
                    doc:ShowDocument{}
                end
            end),
        }
        if not isObstacle then
            local beat = B.CurrentBeat(session)
            local sel = session.selected
            if beat ~= nil and sel ~= nil and sel.kind == "entry" and #beat.rounds > 1 then
                local moveOptions = { { id = "", text = "Move to round..." } }
                for ri, r in ipairs(beat.rounds) do
                    if ri ~= sel.round then
                        moveOptions[#moveOptions + 1] = { id = tostring(ri), text = "Round " .. tostring(r.number) }
                    end
                end
                tools[#tools + 1] = gui.Dropdown{
                    classes = { "sizeXs" },
                    width = 150,
                    height = 24,
                    rmargin = 4,
                    options = moveOptions,
                    idChosen = "",
                    change = function(element)
                        ---@cast element Dropdown
                        local target = tonumber(element.idChosen)
                        if target ~= nil then
                            Do(function() B.MoveEntry(session, sel.round, sel.index, target) end)
                        end
                    end,
                }
            end
            tools[#tools + 1] = ConfirmButton("Delete entry", function()
                Do(function() B.DeleteEntry(session, entry) end)
            end)
        else
            tools[#tools + 1] = ConfirmButton("Delete obstacle", function()
                session.selected = nil
                Commit("Deleted an obstacle.", E.DeleteElement(parse, session.texts, entry.line, 2))
            end)
        end
        children[#children + 1] = Row(tools, { fit = true, tmargin = 10 })
        children[#children + 1] = textEditor

        return children
    end

    --- the editor for a delve's own settings ---
    local function DelveEditor(delve)
        local parse = session.parse
        local children = {}
        children[#children + 1] = Label("DELVE: " .. string.upper(delve.name), { "mbHeading" }, { color = OBSTACLE_COLOR })
        children[#children + 1] = Label(string.format("In the journal document '%s'. The whole delve is one hero's turn: they meet obstacles, find chests, and press deeper (losing a Recovery) or turn back.", B.SourceName(session, delve.line)), { "mbSub" })

        children[#children + 1] = gui.Check{
            classes = { "sizeXs" },
            fontSize = 14,
            width = 520,
            height = 24,
            tmargin = 6,
            text = "In sequence: obstacles come in written order, pressing on is free (a story chain)",
            value = delve.ordered == true,
            change = function(element)
                if element.value then
                    Commit("Delve set to in sequence.", One(E.InsertBlockAfter(parse, session.texts, delve.line, { "Order: in sequence" })))
                elseif delve.orderLines ~= nil then
                    Commit("Delve set to random.", One(E.PatchExpanded(parse, delve.orderLines[1], delve.orderLines[2], {})))
                end
            end,
        }
        if not delve.ordered then
            local function WriteChest(lo, hi)
                lo, hi = tonumber(lo), tonumber(hi)
                if lo == nil or hi == nil or lo < 1 or hi < lo then
                    session.status = "A chest interval is two numbers, low to high (e.g. 1 and 2)."
                    Refresh()
                    return
                end
                local line = cond(lo == hi, string.format("Chest: every %d obstacles", lo), string.format("Chest: every %d-%d obstacles", lo, hi))
                if delve.chestLines ~= nil then
                    Commit("Changed the chest interval.", One(E.PatchExpanded(parse, delve.chestLines[1], delve.chestLines[2], { line })))
                else
                    Commit("Set the chest interval.", One(E.InsertBlockAfter(parse, session.texts, delve.line, { line })))
                end
            end
            children[#children + 1] = Row({
                gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", rmargin = 6, text = "A chest every" },
                TextBox(tostring(delve.chestEvery[1]), function(text) WriteChest(text, delve.chestEvery[2]) end, { width = 40, height = 24 }),
                gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", hmargin = 6, text = "to" },
                TextBox(tostring(delve.chestEvery[2]), function(text) WriteChest(delve.chestEvery[1], text) end, { width = 40, height = 24 }),
                gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", lmargin = 6, text = "obstacles" },
            }, { fit = true, tmargin = 4 })
        end

        children[#children + 1] = Label("Intro", { "mbFieldLabel" })
        children[#children + 1] = TextBox(delve.intro, function(text)
            Commit("Edited the delve intro.", E.SetProse(parse, session.texts, delve.introLines, delve.line, text))
        end, { multiline = true, placeholder = "Notes for the delve (optional)." })

        --the sections: which exist, and buttons for the missing ones.
        local SECTIONS = {
            { key = "chest", heading = "Chest", text = "PC pries open a dusty chest.", note = "a chest is found" },
            { key = "continue", heading = "Continue", text = "PC peers deeper into the dark.", note = "between obstacles" },
            { key = "leave", heading = "Leave", text = "PC turns back toward the light.", note = "turning back" },
            { key = "forced", heading = "Forced Out", text = "Exhausted, PC staggers out.", note = "at 0 Recoveries" },
            { key = "finish", heading = "End", text = "PC has done it.", note = "the last step of an in-sequence delve" },
        }
        children[#children + 1] = Label("Scenes of the delve (pick one on the board to edit it)", { "mbFieldLabel" })
        local missing = {}
        for _, sec in ipairs(SECTIONS) do
            local present = delve.sections[sec.key]
            children[#children + 1] = Label(string.format("%s %s -- %s", cond(present ~= nil, "[x]", "[ ]"), sec.heading, sec.note), { cond(present ~= nil, "mbRule", "mbSub") })
            if present == nil and (sec.key ~= "finish" or delve.ordered) then
                missing[#missing + 1] = sec
            end
        end
        local addButtons = {}
        for _, sec in ipairs(missing) do
            local s = sec
            addButtons[#addButtons + 1] = SmallButton("+ " .. s.heading, function()
                local block = { "## " .. s.heading, "", s.text }
                if s.key == "chest" then
                    block[#block + 1] = ""
                    for _, l in ipairs(E.TableLines{ name = "Treasure", dice = "1d6", rows = { { lo = 1, hi = 3, text = "You gain 1 Healing Potion" }, { lo = 4, hi = 6, text = "+1 hero token" } } }) do
                        block[#block + 1] = l
                    end
                end
                Commit("Added a delve section.", E.InsertAfterElement(parse, session.texts, delve.line, 1, block))
            end)
        end
        if #addButtons > 0 then
            children[#children + 1] = Row(addButtons, { fit = true })
        end

        local textEditor = TextEditorPanel(delve.line, 1, "The whole delve as written.")
        children[#children + 1] = Row({
            SmallButton("Edit delve as text", function() textEditor:SetClass("collapsed", not textEditor:HasClass("collapsed")) end),
        }, { fit = true, tmargin = 8 })
        children[#children + 1] = textEditor
        return children
    end

    --- the board ---
    local function EntryCard(entry, selection, isSelected)
        local color = cond(entry.kind == "threat", THREAT_COLOR, cond(entry.kind == "obstacle" or entry.kind == "delvesection", OBSTACLE_COLOR, OPPORTUNITY_COLOR))
        local kindLabel = cond(entry.kind == "delvesection", "DELVE SCENE", string.upper(entry.kind))
        local tags = {}
        if entry.required then tags[#tags + 1] = "Required" end
        if entry.locked then tags[#tags + 1] = "Locked" end
        if entry.temporary then tags[#tags + 1] = "Temporary" end
        local tests, secrets = 0, 0
        for _, o in ipairs(entry.options) do
            if o.roll ~= nil then tests = tests + 1 end
            if EncounterScript.OptionIsSecret(o) then secrets = secrets + 1 end
        end
        local parts = { string.format("%d option%s", #entry.options, cond(#entry.options == 1, "", "s")) }
        if entry.kind == "delvesection" then
            parts = { string.format("%d scene line%s", #(entry.sceneLines or {}), cond(#(entry.sceneLines or {}) == 1, "", "s")) }
            if entry.table ~= nil then parts[#parts + 1] = "treasure table" end
        end
        if secrets > 0 then parts[#parts + 1] = string.format("%d secret", secrets) end
        if entry.scripted and entry.kind ~= "delvesection" then parts[#parts + 1] = "scene" end
        local warnings = {}
        for _, w in ipairs(B.WarningsIn(session, entry.line, 2)) do
            if not w.textOnly then
                warnings[#warnings + 1] = w
            end
        end
        return gui.Panel{
            classes = { "mbCard", cond(isSelected, "selected", nil) },
            borderColor = cond(isSelected, nil, color),
            click = function()
                session.selected = selection
                Refresh()
                --a new entry opens at its top (1 is the top of a vscroll).
                if editorPanel ~= nil and editorPanel.valid then
                    editorPanel.vscrollPosition = 1
                end
            end,
            Row({
                gui.Label{ fontSize = 11, bold = true, color = color, width = "auto", height = "auto", valign = "center", rmargin = 6,
                    text = kindLabel },
                gui.Label{ fontSize = 15, bold = true, width = "100%-110", height = "auto", textWrap = true, text = entry.name },
            }),
            Label(table.concat(parts, " - ") .. cond(#tags > 0, "  |  " .. table.concat(tags, ", "), ""), { "mbSub" }),
            (function()
                if #warnings == 0 then
                    return nil
                end
                return Label(string.format("%d problem%s", #warnings, cond(#warnings == 1, "", "s")), { "mbProblem" })
            end)(),
        }
    end

    local function Board()
        local children = {}
        local beat = B.CurrentBeat(session)
        if beat == nil then
            children[1] = Label("This script has no '# Montage' beat yet.", { "mbHeading" })
            return children
        end
        local parse = session.parse

        children[#children + 1] = Label("Intro (shown in the header for the whole montage)", { "mbFieldLabel" })
        children[#children + 1] = TextBox(beat.intro, function(text)
            Commit("Edited the montage intro.", E.SetProse(parse, session.texts, beat.introLines, beat.line, text))
        end, { multiline = true, placeholder = "The party's standing context." })

        for ri, round in ipairs(beat.rounds) do
            local roundIndex = ri
            children[#children + 1] = Label(cond(round.implicit, "Round 1 (no round heading)", "Round " .. tostring(round.number)), { "mbHeading" }, { tmargin = 12 })
            --party-size trim lines.
            for _, d in ipairs(round.scaling or {}) do
                local directive = d
                children[#children + 1] = Row({
                    TextBox(directive.text, function(text)
                        Commit("Edited a party-size line.", E.SetLine(parse, directive.line, E.LineText(text)))
                    end, { width = "100%-90", height = 24 }),
                    SmallButton("Remove", function()
                        Commit("Removed a party-size line.", E.DeleteLine(parse, directive.line))
                    end),
                })
            end
            local opps, threats = 0, 0
            for _, e in ipairs(round.entries) do
                if e.kind == "threat" then threats = threats + 1 else opps = opps + 1 end
            end
            children[#children + 1] = Label(string.format("%d opportunities, %d threats introduced. A round needs about 6 for a full party; trim for 4 and 5 heroes.", opps, threats), { "mbSub" })
            if not round.implicit then
                children[#children + 1] = Row({
                    SmallButton("+ Party-size line", function()
                        local after = round.line
                        if round.scaling ~= nil and #round.scaling > 0 then
                            after = round.scaling[#round.scaling].line
                        end
                        local patch, why = E.PatchAfter(parse, after, { E.ScalingLine{ min = 4, max = 4, removals = { opportunity = 1 } } })
                        Commit("Added a party-size line.", patch ~= nil and { patch } or nil, why)
                    end),
                }, { fit = true })
            end
            for ei, e in ipairs(round.entries) do
                local sel = { kind = "entry", round = roundIndex, index = ei }
                local s = session.selected
                local isSelected = s ~= nil and s.kind == "entry" and s.round == roundIndex and s.index == ei
                children[#children + 1] = EntryCard(e, sel, isSelected)
            end
            children[#children + 1] = Row({
                SmallButton("+ Opportunity", function() Do(function() B.AddEntry(session, roundIndex, "opportunity") end) end),
                SmallButton("+ Threat", function() Do(function() B.AddEntry(session, roundIndex, "threat") end) end),
            }, { fit = true })
        end
        children[#children + 1] = Row({
            SmallButton("+ Round", function() Do(function() B.AddRound(session) end) end),
        }, { fit = true, tmargin = 8 })

        --the delves this montage leads into: settings, obstacles and scenes.
        local DELVE_SECTION_ORDER = { "chest", "continue", "leave", "forced", "finish" }
        for _, d in ipairs(B.Delves(session)) do
            local delve = d.delve
            local key = d.key
            local s = session.selected
            local delveSelected = s ~= nil and s.kind == "delve" and s.delve == key
            children[#children + 1] = gui.Panel{
                classes = { "mbCard", cond(delveSelected, "selected", nil) },
                borderColor = cond(delveSelected, nil, OBSTACLE_COLOR),
                tmargin = 14,
                click = function()
                    session.selected = { kind = "delve", delve = key }
                    Refresh()
                    if editorPanel ~= nil and editorPanel.valid then
                        editorPanel.vscrollPosition = 1
                    end
                end,
                Label("DELVE: " .. delve.name, { "mbHeading" }, { color = OBSTACLE_COLOR, bmargin = 0 }),
                Label(string.format("%s; %d obstacle%s%s. Click for its settings.",
                    cond(delve.ordered, "In sequence", "Random obstacles"), #delve.obstacles, cond(#delve.obstacles == 1, "", "s"),
                    cond(delve.ordered, "", string.format(", a chest every %d-%d", delve.chestEvery[1], delve.chestEvery[2]))), { "mbSub" }),
            }
            for oi, ob in ipairs(delve.obstacles) do
                local sel = { kind = "obstacle", delve = key, index = oi }
                local isSelected = s ~= nil and s.kind == "obstacle" and s.delve == key and s.index == oi
                children[#children + 1] = EntryCard(ob, sel, isSelected)
            end
            for _, sectionKey in ipairs(DELVE_SECTION_ORDER) do
                local section = delve.sections[sectionKey]
                if section ~= nil then
                    local sel = { kind = "section", delve = key, key = sectionKey }
                    local isSelected = s ~= nil and s.kind == "section" and s.delve == key and s.key == sectionKey
                    children[#children + 1] = EntryCard(section, sel, isSelected)
                end
            end
            children[#children + 1] = Row({
                SmallButton("+ Obstacle", function() Do(function() B.AddObstacle(session, key) end) end),
            }, { fit = true })
        end
        return children
    end

    local function ProblemsFooterText()
        local n = 0
        for _, w in ipairs(LocatedWarnings(session)) do
            if not w.textOnly then
                n = n + 1
            end
        end
        return cond(n == 0, "No problems in the script.", string.format("%d problem%s in the whole script (open the validator for all of them).", n, cond(n == 1, "", "s")))
    end

    Refresh = function()
        if boardBody == nil or not boardBody.valid then
            return
        end
        local ok, children = pcall(Board)
        if not ok then
            children = { Label("Board failed: " .. tostring(children), { "mbProblem" }) }
        end
        boardBody.children = children

        local entry = B.SelectedEntry(session)
        local editorChildren
        local sel = session.selected
        local selectedDelve = sel ~= nil and sel.kind == "delve" and session.parse.delves[sel.delve] or nil
        if selectedDelve ~= nil then
            local okDelve, built = pcall(DelveEditor, selectedDelve)
            if okDelve then
                editorChildren = built
            else
                editorChildren = { Label("Editor failed: " .. tostring(built), { "mbProblem" }) }
            end
        elseif entry == nil then
            editorChildren = {
                Label("Pick an opportunity, threat or delve obstacle on the left to edit it.", { "mbHeading" }),
                Label("Every change is written straight into the journal document it came from, and the script is re-checked with the game's own parser. Undo takes back one change at a time.", { "mbSub" }),
            }
        else
            local okEditor, built = pcall(EntryEditor, entry)
            if okEditor then
                editorChildren = built
            else
                editorChildren = { Label("Editor failed: " .. tostring(built), { "mbProblem" }) }
            end
        end
        editorBody.children = editorChildren
        statusLabel.text = (session.status ~= "" and (session.status .. "   ") or "") .. ProblemsFooterText()
        titleLabel.text = string.format("Montage Builder: %s", tostring(session.names[session.rootId]))
        if beatDropdown ~= nil then
            local options = {}
            for i, m in ipairs(session.montages) do
                options[#options + 1] = { id = tostring(i), text = string.format("Montage %d (beat %d)", i, m.index) }
            end
            beatDropdown.options = options
            beatDropdown.idChosen = tostring(session.beatIndex)
            beatDropdown:SetClass("collapsed", #options < 2)
        end
    end

    titleLabel = gui.Label{ classes = { "sizeXl", "bold" }, width = "auto", height = "auto", halign = "left", valign = "center", text = "Montage Builder" }
    statusLabel = gui.Label{ classes = { "mbSub" }, width = "100%", height = "auto", valign = "center", textWrap = true, text = "" }
    beatDropdown = gui.Dropdown{
        classes = { "sizeXs", "collapsed" },
        width = 200,
        height = 26,
        valign = "center",
        lmargin = 12,
        options = {},
        change = function(element)
            ---@cast element Dropdown
            session.beatIndex = tonumber(element.idChosen) or 1
            session.selected = nil
            Refresh()
        end,
    }

    --each scroll area holds one auto-height body at its top: a flow panel
    --taller than its content would spread the children over its height.
    boardBody = gui.Panel{ width = "100%", height = "auto", flow = "vertical", valign = "top" }
    editorBody = gui.Panel{ width = "100%", height = "auto", flow = "vertical", valign = "top" }
    boardPanel = gui.Panel{
        width = 440,
        height = "100%",
        flow = "vertical",
        vscroll = true,
        rpad = 14,
        borderBox = true,
        boardBody,
    }
    editorPanel = gui.Panel{
        width = "100%-460",
        height = "100%",
        flow = "vertical",
        vscroll = true,
        lmargin = 16,
        rpad = 14,
        borderBox = true,
        editorBody,
    }

    local window = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "none",
        bgimage = "panels/square.png",
        bgcolor = "#000000c0",
        styles = ThemeEngine.MergeStyles(STYLES),

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            close()
        end,

        --other clients and the journal: pick up their edits.
        thinkTime = 1,
        think = function(element)
            if B.PollExternal(session) then
                Refresh()
            end
        end,

        gui.Panel{
            classes = { "framedPanel" },
            width = "94%",
            height = "92%",
            halign = "center",
            valign = "center",
            flow = "vertical",
            pad = 16,
            borderBox = true,

            gui.Panel{
                width = "100%",
                height = 34,
                flow = "horizontal",
                titleLabel,
                beatDropdown,
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    halign = "right",
                    valign = "center",
                    flow = "horizontal",
                SmallButton("Undo", function() Do(function() B.Undo(session) end) end),
                SmallButton("Test this montage", function()
                    close()
                    pcall(function() EncounterTest.ShowDialog("montage") end)
                end),
                SmallButton("Validator", function()
                    close()
                    pcall(function() DockablePanel.ShowPanelByName(EncounterScriptValidator.panelName) end)
                end),
                SmallButton("Close", function() close() end),
                },
            },

            gui.Panel{
                width = "100%",
                height = "100%-80",
                flow = "horizontal",
                tmargin = 8,
                boardPanel,
                editorPanel,
            },

            gui.Panel{
                width = "100%",
                height = 30,
                flow = "horizontal",
                statusLabel,
            },
        },
    }

    Refresh()
    return window
end

--Open the builder on the current map's script.
function B.Open(docid)
    if not dmhub.isDM then
        print("Montage Builder: only the Director can edit the encounter script.")
        return
    end
    local gamehud = GameHud.instance
    if not gamehud then
        return
    end
    local session, why = B.Load(docid)
    if session == nil then
        print("Montage Builder: " .. tostring(why))
        return
    end
    B.session = session
    local window = B.CreateWindow(session, function()
        gamehud:CloseModal()
    end)
    gamehud:ShowModal(window)
end

Commands.Register{
    name = "Montage Builder",
    identifier = "eotwbuilder",
    icon = "panels/initiative/initiative-icon.png",
    menu = "game",
    group = "eotwtest",
    execute = function()
        B.Open()
    end,
    filtered = function()
        return not dmhub.isDM
    end,
}

pcall(function()
    Commands.RegisterMacro{
        name = "eotwbuilder",
        summary = "open the Encounter of the Week Montage Builder",
        doc = "Usage: /eotwbuilder\nOpens the Montage Builder on the current map's Encounter of the Week script: the montage's rounds and entries on a board, and an editor for each entry. Changes are written straight into the script's journal documents.",
        command = function()
            B.Open()
        end,
    }
end)
