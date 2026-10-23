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
--Open it with /eotwbuilder, or from Game > Encounter Builder (the whole
--script, EncounterScriptBuilder.lua) through a montage's "Open in the
--Montage Builder".

EncounterMontageBuilder = {}
local B = EncounterMontageBuilder
local E = EncounterScriptEdit

local T = UIText.T
local TP = UIText.Plural

local RULE_COLOR = "#7fd97f"
local PROBLEM_COLOR = "#e88a8a"
local OPPORTUNITY_COLOR = "#6fae7a"
local THREAT_COLOR = "#c46a6a"
local OBSTACLE_COLOR = "#a08ac4"

local CHARACTERISTICS = { "Might", "Agility", "Reason", "Intuition", "Presence" }
local TIER_RANGES = { T("author.montage_builder.rules.tier1_range"), "12-16", "17+", T("author.montage_builder.rules.critical_range") }

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
--session, or nil + why. `pendingDoc` is a document made this frame that
--the documents table does not hold yet ("Create the script").
function B.Load(docid, pendingDoc)
    local mapid = game.currentMapId
    if docid == nil then
        local script = nil
        pcall(function() script = EncounterMontage.FindMapScript(true) end)
        docid = script ~= nil and script.docid or nil
    end
    if docid == nil then
        return nil, "This map has no Encounter of the Week script yet. Write a '# Montage' in a journal document filed under this map, then open the builder."
    end
    local doc = DocsTable()[docid] or pendingDoc
    if doc == nil then
        return nil, "The script document is missing."
    end
    local session = {
        rootId = docid,
        mapid = mapid,
        texts = { [docid] = DocText(doc) },
        names = { [docid] = doc.description or T("author.montage_builder.load.script_fallback_name") },
        pending = {},
        uploading = {},
        undo = {},
        status = "",
    }
    if DocsTable()[docid] == nil then
        session.pending[docid] = { name = session.names[docid], doc = doc }
    end
    B.Reparse(session)
    return session
end

--Write the changed documents back to the journal, a frame apart (a second
--upload to the same table in one frame is dropped). The first waits a
--little too, behind any document created or renamed this frame.
--`annotations` ({ [docid] = table }) replaces those documents' [[tag]]
--data in the same upload (see B.CommitTexts).
local function Upload(session, changed, annotations)
    local delay = 0.1
    for docid, text in pairs(changed) do
        local id, newText = docid, text
        local newAnnotations = annotations ~= nil and annotations[docid] or nil
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
                if newAnnotations ~= nil then
                    doc.annotations = DeepCopy(newAnnotations)
                end
                doc:Upload()
                return
            end
            if doc == nil then
                return
            end
            local original = DeepCopy(doc)
            doc:SetTextContent(newText)
            if newAnnotations ~= nil then
                --script documents are journal (markdown) documents.
                ---@cast doc MarkdownDocument
                doc.annotations = DeepCopy(newAnnotations)
            end
            doc:Upload(original)
        end)
        delay = delay + 0.1
    end
end

--A document's [[tag]] data as it is now (live, else the copy made here).
local function DocAnnotations(session, docid)
    local doc = DocsTable()[docid]
    if doc == nil and session.pending[docid] ~= nil then
        doc = session.pending[docid].doc
    end
    if doc == nil then
        return nil
    end
    local annotations = nil
    pcall(function() annotations = doc:try_get("annotations") end)
    return annotations or {}
end

--Apply new texts. `maps` ({ [docid] = old line -> new line }) asks for the
--documents' [[tag]] data to follow the tags: a journal binds repeated tags
--by order ([[scene]], then "scene-1"...), so moving or deleting a block
--that holds one would hand every later tag of that name the wrong data
--(E.RekeyTags). Undo restores the old data with the old text.
--Returns true when something was written.
function B.CommitTexts(session, what, newTexts, maps)
    local before = {}
    local changed = {}
    local any = false
    for docid, text in pairs(newTexts) do
        if text ~= session.texts[docid] then
            before[docid] = session.texts[docid]
            changed[docid] = text
            any = true
        end
    end
    if not any then
        return false
    end
    local newAnnotations, oldAnnotations = nil, nil
    for docid, map in pairs(maps or {}) do
        if changed[docid] ~= nil then
            local remap, gone = E.RekeyTags(E.Split(before[docid]).lines, E.Split(changed[docid]).lines, map)
            local current = DocAnnotations(session, docid)
            if current ~= nil and E.RekeyChanges(remap, gone) then
                local tagKeys = {}
                for k in pairs(remap) do tagKeys[k] = true end
                for _, k in ipairs(gone) do tagKeys[k] = true end
                local result = {}
                for k, v in pairs(current) do
                    if not tagKeys[k] then
                        result[k] = v
                    end
                end
                for oldKey, newKey in pairs(remap) do
                    if current[oldKey] ~= nil then
                        result[newKey] = current[oldKey]
                    end
                end
                newAnnotations = newAnnotations or {}
                oldAnnotations = oldAnnotations or {}
                newAnnotations[docid] = result
                oldAnnotations[docid] = DeepCopy(current)
            end
        end
    end
    for docid, text in pairs(changed) do
        session.texts[docid] = text
    end
    session.undo[#session.undo + 1] = { texts = before, annotations = oldAnnotations, what = what }
    Upload(session, changed, newAnnotations)
    B.Reparse(session)
    session.status = what
    return true
end

--Apply an edit: patches from EncounterScriptEdit, or nil + why. Returns
--true when something was written. opts.keepTags: the edit moves or deletes
--whole blocks, so [[tag]] data is re-keyed to follow the tags.
function B.Commit(session, what, patches, why, opts)
    if patches == nil then
        session.status = T("author.montage_builder.status.not_changed", { why = tostring(why or T("author.montage_builder.status.edit_failed")) })
        return false
    end
    if #patches == 0 then
        return false
    end
    local ok, changed = pcall(E.Apply, session.texts, patches)
    if not ok then
        session.status = T("author.montage_builder.status.not_changed", { why = tostring(changed) })
        return false
    end
    local maps = nil
    if opts ~= nil and opts.keepTags then
        maps = {}
        local byDoc = {}
        for _, p in ipairs(patches) do
            byDoc[p.docid] = byDoc[p.docid] or {}
            table.insert(byDoc[p.docid], p)
        end
        for docid, list in pairs(byDoc) do
            maps[docid] = E.PatchLineMap(#E.Split(session.texts[docid]).lines, list)
        end
    end
    return B.CommitTexts(session, what, changed, maps)
end

function B.Undo(session)
    local step = table.remove(session.undo)
    if step == nil then
        session.status = T("author.montage_builder.status.nothing_to_undo")
        return false
    end
    local changed = {}
    for docid, text in pairs(step.texts) do
        session.texts[docid] = text
        changed[docid] = text
    end
    Upload(session, changed, step.annotations)
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
    session.status = T("author.montage_builder.status.undid", { what = tostring(step.what) })
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
        session.status = T("author.montage_builder.status.updated_from_journal")
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

--The names the scene forms offer in their dropdowns, sorted. Built once per
--window (the bestiary is large); B.Open clears it.
---@return table
function B.Lists()
    if B._lists ~= nil then
        return B._lists
    end
    local function Names(tableName, keep)
        local names, seen = {}, {}
        pcall(function()
            for _, row in unhidden_pairs(dmhub.GetTable(tableName) or {}) do
                local name = row.name
                if type(name) == "string" and trim(name) ~= "" and not seen[lower(name)] and (keep == nil or keep(row)) then
                    seen[lower(name)] = true
                    names[#names + 1] = trim(name)
                end
            end
        end)
        table.sort(names)
        return names
    end
    local monsters, seen = {}, {}
    pcall(function()
        for _, asset in pairs(assets.monsters or {}) do
            local name = asset.name
            if not asset.hidden and type(name) == "string" and trim(name) ~= "" and not seen[lower(name)] then
                seen[lower(name)] = true
                monsters[#monsters + 1] = trim(name)
            end
        end
    end)
    table.sort(monsters)
    local capabilities = {}
    pcall(function()
        for _, cap in ipairs(TestRiders.CAPABILITIES) do
            capabilities[#capabilities + 1] = cap.key
        end
    end)
    table.sort(capabilities)
    --monster keywords ("Goblin", "Undead") for "know the Stamina of ...".
    local keywords, seenKeyword = {}, {}
    pcall(function()
        for _, asset in pairs(assets.monsters or {}) do
            if not asset.hidden then
                pcall(function()
                    --the stat block's own keywords; Keywords() would evaluate every modifier.
                    for keyword, _ in pairs(asset.properties:try_get("keywords") or {}) do
                        local k = trim(tostring(keyword))
                        if k ~= "" and not string.find(k, " ", 1, true) and not seenKeyword[lower(k)] then
                            seenKeyword[lower(k)] = true
                            keywords[#keywords + 1] = k
                        end
                    end
                end)
            end
        end
    end)
    table.sort(keywords)
    --zone keywords: a clause names one word ("Trap", "Start2").
    local zones = {}
    for _, name in ipairs(Names("environmentalKeywords")) do
        if not string.find(name, " ", 1, true) then
            zones[#zones + 1] = name
        end
    end
    --the objects on this map, by name (a reveal names one the author left inactive).
    local objects, seenObject = {}, {}
    pcall(function()
        for _, floor in ipairs((game.currentMap and game.currentMap.floors) or {}) do
            for _, obj in pairs(floor.objects or {}) do
                local name = nil
                pcall(function() name = obj.name end)
                if type(name) == "string" and trim(name) ~= "" and not seenObject[lower(name)] then
                    seenObject[lower(name)] = true
                    objects[#objects + 1] = trim(name)
                end
            end
        end
    end)
    table.sort(objects)
    local lists = {
        monsters = monsters,
        items = Names("tbl_Gear"),
        keywords = keywords,
        zones = zones,
        objects = objects,
        damageTypes = EncounterScript.DAMAGE_TYPES,
        languages = Names(Language.tableName),
        ancestries = Names(Race.tableName),
        classes = Names(Class.tableName, function(row) return not row.isSubclass end),
        careers = Names(Background.tableName),
        perks = Names(CharacterFeat.tableName),
        skills = B.SkillOptions(),
        capabilities = capabilities,
    }
    B._lists = lists
    return lists
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
        session.status = T("author.montage_builder.status.not_added_no_round")
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
    if B.Commit(session, cond(kind == "threat", T("author.montage_builder.status.added_threat", { name = name }), T("author.montage_builder.status.added_opportunity", { name = name })), { patch }) then
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
                local ok = B.Commit(session, T("author.montage_builder.status.deleted", { name = tostring(entry.name) }), { E.Patch(session.rootId, rootLine, last, {}) })
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
                    session.status = T("author.montage_builder.status.deleted_hid_document", { name = tostring(entry.name), document = tostring(session.names[docid]) })
                end
                session.selected = nil
                return ok
            end
        end
    end
    local patches, why = E.DeleteElement(parse, session.texts, entry.line, 2)
    session.selected = nil
    return B.Commit(session, T("author.montage_builder.status.deleted", { name = tostring(entry.name) }), patches, why)
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
        session.status = T("author.montage_builder.status.entry_needs_name")
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
        return B.Commit(session, T("author.montage_builder.status.renamed_entry"), nil, why)
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
    local ok = B.Commit(session, T("author.montage_builder.status.renamed", { old = tostring(entry.name), new = name }), patches)
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
    return B.Commit(session, T("author.montage_builder.status.added_round", { number = number }),
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
        session.status = T("author.montage_builder.status.not_moved_no_round")
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
        session.status = T("author.montage_builder.status.not_moved_shared")
        return false
    end
    --take the blank line after it too, when it would leave two in a row.
    if trim(rootLines[removeLast + 1] or "x") == "" and trim(rootLines[removeFirst - 1] or "x") == "" then
        removeLast = removeLast + 1
    end
    if anchor >= removeFirst - 1 and anchor <= removeLast then
        session.status = T("author.montage_builder.status.already_there")
        return false
    end
    local patches = {
        E.Patch(session.rootId, removeFirst, removeLast, {}),
        E.InsertBlockAfterDocLine(session.texts, session.rootId, anchor, lines),
    }
    local ok = B.Commit(session, T("author.montage_builder.status.moved", { name = tostring(entry.name), round = tostring(beat.rounds[toRound].number) }), patches)
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
        session.status = T("author.montage_builder.status.not_added", { why = tostring(why) })
        return false
    end
    for _, p in ipairs(optionPatches) do
        patches[#patches + 1] = p
    end
    local ok = B.Commit(session, T("author.montage_builder.status.added_delve", { name = name }), patches)
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
    return B.Commit(session, T("author.montage_builder.status.added_obstacle"), patches, why)
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
            element.text = T("author.montage_builder.confirm_again")
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
            session.status = T("author.montage_builder.status.error", { error = tostring(err) })
        end
        Refresh()
    end

    --opts.keepTags: whole blocks move or go, so [[tag]] data follows its tags.
    local function Commit(what, patches, why, opts)
        Do(function() B.Commit(session, what, patches, why, opts) end)
    end

    --- scene lines ---
    --A scene is one step per line, each shown as a small form for its kind
    --(narration, speech, an entrance, a branch...). A form writes its line
    --back whole, keeping the line's indentation. `steps` are the parser's
    --{ text, line } list; `anchor` is the expanded line new steps go after
    --when the list is empty. `ctx` = { actors (entry.actors), options (the
    --entry's options, for "PC chose"), part = "intro"|"option"|"outcome",
    --entry } -- only an outcome scene knows the roll's tier.
    local STEP_STYLE = {
        narrate = { T("author.montage_builder.scene.step_narration"), "#b0b0b0" },
        say = { T("author.montage_builder.scene.step_says"), "#ffffff" },
        enter = { T("author.montage_builder.scene.step_enters"), "#9fd0ff" },
        exit = { T("author.montage_builder.scene.step_exits"), "#9fd0ff" },
        emote = { T("author.montage_builder.scene.step_emote"), "#e8c27a" },
        ["if"] = { T("author.montage_builder.scene.step_if"), "#c9a4ff" },
        ["elseif"] = { T("author.montage_builder.scene.step_else_if"), "#c9a4ff" },
        ["else"] = { T("author.montage_builder.scene.step_else"), "#c9a4ff" },
        ["end"] = { T("author.montage_builder.scene.step_end"), "#c9a4ff" },
    }
    local STEP_TYPES = {
        { id = "narrate", text = T("author.montage_builder.scene.type_narration") },
        { id = "pcsay", text = T("author.montage_builder.scene.type_pc_says") },
        { id = "say", text = T("author.montage_builder.scene.type_character_says") },
        { id = "enter", text = T("author.montage_builder.scene.type_character_enters") },
        { id = "exit", text = T("author.montage_builder.scene.type_character_exits") },
        { id = "emote", text = T("author.montage_builder.scene.type_emote") },
        { id = "branch", text = T("author.montage_builder.scene.type_branch") },
    }
    local INDENT = "    "

    --The predicates a branch condition row offers. `list` names a B.Lists()
    --list (or "options" / "tiers"); `free` takes typed text instead.
    local PREDICATES = {
        { id = "ancestry", text = T("author.montage_builder.condition.predicate_ancestry"), list = "ancestries" },
        { id = "class", text = T("author.montage_builder.condition.predicate_class"), list = "classes" },
        { id = "career", text = T("author.montage_builder.condition.predicate_career"), list = "careers" },
        { id = "speaks", text = T("author.montage_builder.condition.predicate_speaks"), list = "languages" },
        { id = "skilled", text = T("author.montage_builder.condition.predicate_skilled"), list = "skills" },
        { id = "perk", text = T("author.montage_builder.condition.predicate_perk"), list = "perks" },
        { id = "can", text = T("author.montage_builder.condition.predicate_can"), list = "capabilities" },
        { id = "chose", text = T("author.montage_builder.condition.predicate_chose"), list = "options" },
        { id = "tier", text = T("author.montage_builder.condition.predicate_tier"), list = "tiers" },
        { id = "has", text = T("author.montage_builder.condition.predicate_has"), free = "a lantern" },
        { id = "is", text = T("author.montage_builder.condition.predicate_is"), free = "small" },
        { id = "custom", text = T("author.montage_builder.condition.predicate_custom"), free = "PC worships Grole" },
    }
    local TIER_OPTIONS = {
        { id = "1", text = T("author.montage_builder.condition.tier1") },
        { id = "2", text = T("author.montage_builder.condition.tier2") },
        { id = "3", text = T("author.montage_builder.condition.tier3") },
        { id = "4", text = T("author.montage_builder.condition.critical") },
    }

    --{id, text} options for a dropdown of names, and the id to show for
    --`current`. A current value not in the list is kept, marked.
    local function NameOptions(names, current, first)
        local options = {}
        for _, o in ipairs(first or {}) do
            options[#options + 1] = o
        end
        local chosen = nil
        for _, name in ipairs(names) do
            options[#options + 1] = { id = name, text = name }
            if current ~= nil and lower(name) == lower(current) then
                chosen = name
            end
        end
        for _, o in ipairs(first or {}) do
            if current ~= nil and lower(o.id) == lower(current) then
                chosen = o.id
            end
        end
        if chosen == nil and current ~= nil and trim(current) ~= "" then
            table.insert(options, #(first or {}) + 1, { id = current, text = T("author.montage_builder.not_found_option", { name = current }) })
            chosen = current
        end
        return options, chosen
    end

    local function ActorNames(ctx)
        local names = {}
        for _, a in pairs(ctx.actors or {}) do
            names[#names + 1] = a.name
        end
        table.sort(names)
        return names
    end

    local function PickDropdown(options, chosen, onPick, opts)
        opts = opts or {}
        return gui.Dropdown{
            classes = { "sizeXs" },
            width = opts.width or 140,
            height = 24,
            lmargin = opts.lmargin or 4,
            valign = "center",
            options = options,
            idChosen = chosen,
            hasSearch = opts.search == true or #options > 12,
            menuWidth = opts.menuWidth,
            hover = opts.tooltip ~= nil and gui.Tooltip(opts.tooltip) or nil,
            change = function(element)
                ---@cast element Dropdown
                if element.idChosen ~= chosen then
                    onPick(element.idChosen)
                end
            end,
        }
    end

    local function Word(text, extra)
        local args = { classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", hmargin = 4, text = text }
        for k, v in pairs(extra or {}) do
            args[k] = v
        end
        return gui.Label(args)
    end

    local function SceneEditor(title, steps, anchor, ctx)
        local parse = session.parse
        ctx = ctx or {}
        steps = steps or {}
        local lists = B.Lists()
        local actorNames = ActorNames(ctx)
        local texts = {}
        for i, s in ipairs(steps) do
            texts[i] = s.text
        end

        --a line's own indentation, from its document.
        local function Lead(s)
            local docid, at = E.Source(parse, s.line)
            local raw = E.Split(session.texts[docid] or "").lines[at] or ""
            return string.match(raw, "^(%s*)") or ""
        end
        local function WriteForm(s, form, what)
            Commit(what or T("author.montage_builder.status.edited_scene_line"), E.SetLine(parse, s.line, Lead(s) .. E.SceneStepLine(form)))
        end

        --the lines a new step of type `id` writes (unindented; a branch's
        --body is indented one step).
        local function NewStepLines(id)
            local someone = actorNames[1]
            if id == "pcsay" then
                return { "PC: Hello there!" }
            elseif id == "say" then
                if someone ~= nil then
                    return { someone .. ": Who goes there?" }
                end
                return { "??? (offstage): Who goes there?" }
            elseif id == "enter" then
                local monster = "Goblin Warrior"
                local found = nil
                pcall(function() found = EncounterMontage.FindMonster(monster) end)
                if found == nil and lists.monsters[1] ~= nil then
                    monster = lists.monsters[1]
                end
                return { string.format("Stranger (%s) enters", monster) }
            elseif id == "exit" then
                return { (someone or "Stranger") .. " exits" }
            elseif id == "emote" then
                return { (someone or "PC") .. " is alert" }
            elseif id == "branch" then
                local condText = cond(ctx.part == "outcome", "tier3", "PC speaks " .. (lists.languages[1] or "Caelian"))
                return { "if " .. condText .. " then", INDENT .. "PC looks around.", "end" }
            end
            return { "PC looks around." }
        end

        --insert new lines after step `s` (inside the branch when `s` opens one).
        local function InsertAfter(s, id)
            local form = E.ReadSceneStep(s.text, ctx.actors)
            local lead = Lead(s)
            if form.kind == "if" or form.kind == "elseif" or form.kind == "else" then
                lead = lead .. INDENT
            end
            local lines = {}
            for _, l in ipairs(NewStepLines(id)) do
                lines[#lines + 1] = lead .. l
            end
            Commit(T("author.montage_builder.status.added_scene_step"), One(E.PatchAfter(parse, s.line, lines)))
        end

        --remove steps i..j (expanded lines, one document).
        local function RemoveSteps(i, j, what)
            Commit(what, One(E.PatchExpanded(parse, steps[i].line, steps[j].line, {})))
        end

        --rename a character everywhere in this entry's scenes: their
        --entrances, lines, exits and emotes.
        local function RenameCharacter(oldName, newName)
            newName = (string.gsub(E.LineText(newName), "[():]", ""))
            if trim(newName) == "" or lower(newName) == lower(oldName) then
                return
            end
            if lower(newName) == "pc" then
                session.status = T("author.montage_builder.status.pc_is_the_hero")
                Refresh()
                return
            end
            local patches = {}
            for _, list in ipairs(ctx.allLines or { steps }) do
                for _, s in ipairs(list or {}) do
                    local form = E.ReadSceneStep(s.text, ctx.actors)
                    local hit = false
                    if form.kind == "say" and not form.offstage and lower(form.speaker) == lower(oldName) then
                        form.speaker = newName
                        hit = true
                    elseif (form.kind == "enter" or form.kind == "exit" or form.kind == "emote") and lower(form.name) == lower(oldName) then
                        form.name = newName
                        hit = true
                    end
                    if hit then
                        local p = E.SetLine(parse, s.line, Lead(s) .. E.SceneStepLine(form))
                        if p ~= nil then
                            patches[#patches + 1] = p[1]
                        end
                    end
                end
            end
            Commit(T("author.montage_builder.status.renamed_character", { old = oldName, new = newName }), patches)
        end

        --- one condition (an "if" or "else if" line) ---
        local function ConditionEditor(s, form, i)
            local rows = E.ReadCondition(form.cond)
            local out = {}
            local function Write(newRows)
                form.cond = E.ConditionText(newRows)
                WriteForm(s, form, T("author.montage_builder.status.edited_condition"))
            end
            if rows == nil then
                out[#out + 1] = Row({
                    TextBox(form.cond, function(text)
                        form.cond = E.LineText(text)
                        WriteForm(s, form, T("author.montage_builder.status.edited_condition"))
                    end, { width = "100%-4", height = 24 }),
                })
                out[#out + 1] = Label(T("author.montage_builder.condition.hand_written"), { "mbSub" })
            else
                local classSet = {}
                for _, c in ipairs(lists.classes) do
                    classSet[lower(c)] = true
                end
                local optionNames = {}
                for _, o in ipairs(ctx.options or {}) do
                    optionNames[#optionNames + 1] = o.name
                end
                for ri, row in ipairs(rows) do
                    local index = ri
                    local predicate = row.kind
                    if predicate == "kindred" then
                        predicate = cond(classSet[lower(row.value)], "class", "ancestry")
                    end
                    local pinfo = nil
                    for _, p in ipairs(PREDICATES) do
                        if p.id == predicate then
                            pinfo = p
                        end
                    end
                    ---@cast pinfo -nil
                    local children = {}
                    --one dropdown says how this part joins on and whether it is negated.
                    local lead = cond(index == 1, cond(form.kind == "if", "if", "elseif"), nil)
                    --each join word, plain and negated. "Unless" reads more
                    --naturally than "If not"; the script still says "if not ...".
                    local joinText = {
                        ["if"] = { T("author.montage_builder.condition.join_if"), T("author.montage_builder.condition.join_unless") },
                        ["elseif"] = { T("author.montage_builder.condition.join_else_if"), T("author.montage_builder.condition.join_else_if_not") },
                        ["and"] = { T("author.montage_builder.condition.join_and"), T("author.montage_builder.condition.join_and_not") },
                        ["or"] = { T("author.montage_builder.condition.join_or"), T("author.montage_builder.condition.join_or_not") },
                    }
                    local joinOptions = {}
                    for _, j in ipairs(cond(index == 1, { "" }, { "and", "or" })) do
                        for _, neg in ipairs({ false, true }) do
                            local text = joinText[lead or j][cond(neg, 2, 1)]
                            joinOptions[#joinOptions + 1] = { id = j .. cond(neg, "-not", ""), text = text }
                        end
                    end
                    local joinId = cond(index == 1, "", row.join or "and") .. cond(row.negate, "-not", "")
                    children[#children + 1] = PickDropdown(joinOptions, joinId, function(id)
                        local j, neg = string.match(id, "^(%a*)(%-?n?o?t?)$")
                        rows[index].join = cond(index == 1 or j == "", nil, j)
                        rows[index].negate = neg == "-not"
                        Write(rows)
                    end, { width = 96, lmargin = 0, tooltip = T("author.montage_builder.condition.join_tooltip") })
                    local predicateOptions = {}
                    for _, p in ipairs(PREDICATES) do
                        predicateOptions[#predicateOptions + 1] = { id = p.id, text = p.text }
                    end
                    children[#children + 1] = PickDropdown(predicateOptions, predicate, function(id)
                        local newRow = { join = row.join, negate = row.negate }
                        for _, p in ipairs(PREDICATES) do
                            if p.id == id then
                                newRow.kind = cond(id == "ancestry" or id == "class", "kindred", id)
                                if p.free ~= nil then
                                    newRow.value = cond(id == "custom", E.ConditionAtomText({ kind = row.kind, value = row.value }), p.free)
                                elseif p.list == "tiers" then
                                    newRow.value = "3"
                                elseif p.list == "options" then
                                    newRow.value = optionNames[1] or "an option"
                                else
                                    newRow.value = lists[p.list][1] or ""
                                end
                            end
                        end
                        rows[index] = newRow
                        Write(rows)
                    end, { width = 170 })
                    if pinfo.free ~= nil then
                        children[#children + 1] = TextBox(row.value, function(text)
                            rows[index].value = E.LineText(text)
                            Write(rows)
                        end, { width = 220, height = 24 })
                    else
                        local options, chosen
                        if pinfo.list == "tiers" then
                            options, chosen = TIER_OPTIONS, row.value
                        elseif pinfo.list == "options" then
                            options, chosen = NameOptions(optionNames, row.value)
                        else
                            options, chosen = NameOptions(lists[pinfo.list], row.value)
                        end
                        children[#children + 1] = PickDropdown(options, chosen, function(id)
                            rows[index].value = id
                            Write(rows)
                        end, { width = 220, menuWidth = 260 })
                    end
                    if #rows > 1 then
                        children[#children + 1] = gui.Button{ classes = { "sizeXs" }, width = 22, height = 22, lmargin = 4, valign = "center", text = "x",
                            hover = gui.Tooltip(T("author.montage_builder.condition.remove_part_tooltip")),
                            click = function()
                                table.remove(rows, index)
                                rows[1].join = nil
                                Write(rows)
                            end }
                    end
                    out[#out + 1] = Row(children, { fit = true, vmargin = 1 })
                    if pinfo.list == "tiers" and ctx.part ~= "outcome" then
                        out[#out + 1] = Label(T("author.montage_builder.condition.tier_never_true"), { "mbProblem" })
                    end
                end
                local addRow = {
                    SmallButton(T("author.montage_builder.condition.add_and"), function()
                        local copy = DeepCopy(rows[#rows])
                        copy.join = "and"
                        rows[#rows + 1] = copy
                        Write(rows)
                    end),
                    SmallButton(T("author.montage_builder.condition.add_or"), function()
                        local copy = DeepCopy(rows[#rows])
                        copy.join = "or"
                        rows[#rows + 1] = copy
                        Write(rows)
                    end),
                }
                out[#out + 1] = Row(addRow, { fit = true, vmargin = 1 })
                local hasAnd, hasOr = false, false
                for ri = 2, #rows do
                    if rows[ri].join == "or" then hasOr = true else hasAnd = true end
                end
                if hasAnd and hasOr then
                    out[#out + 1] = Label(T("author.montage_builder.condition.and_before_or"), { "mbSub" })
                end
            end
            local _, problems = EncounterScript.ParseCondition(form.cond or "")
            for _, p in ipairs(problems or {}) do
                out[#out + 1] = Label(p, { "mbProblem" })
            end
            return out
        end

        --- one step's form (everything right of the kind label) ---
        --Returns the form's controls, and whether they fill the row's width
        --(a text box does); controls that do not are kept together on the left.
        local function StepForm(s, form, i)
            local kind = form.kind
            if kind == "narrate" then
                return { TextBox(form.text, function(text)
                    form.text = text
                    WriteForm(s, form)
                end, { width = "100%-4", height = 24, placeholder = T("author.montage_builder.scene.narration_placeholder") }) }, true
            elseif kind == "say" then
                local speakerOptions = { { id = "PC", text = T("author.montage_builder.scene.who_pc") } }
                for _, n in ipairs(actorNames) do
                    speakerOptions[#speakerOptions + 1] = { id = n, text = n }
                end
                speakerOptions[#speakerOptions + 1] = { id = "@unknown", text = T("author.montage_builder.scene.speaker_unknown_voice") }
                speakerOptions[#speakerOptions + 1] = { id = "@custom", text = T("author.montage_builder.scene.speaker_named_voice") }
                local chosen = form.speaker
                if form.offstage then
                    chosen = cond(form.speaker == "???", "@unknown", "@custom")
                end
                ---@type Panel[]
                local out = {
                    PickDropdown(speakerOptions, chosen, function(id)
                        if id == "@unknown" then
                            form.offstage, form.speaker, form.emote = true, "???", nil
                        elseif id == "@custom" then
                            form.offstage, form.emote = true, nil
                            if form.speaker == "PC" or form.speaker == "???" then
                                form.speaker = "Voice"
                            end
                        else
                            form.offstage, form.speaker = false, id
                        end
                        WriteForm(s, form)
                    end, { width = 150, lmargin = 0, tooltip = T("author.montage_builder.scene.speaker_tooltip") }),
                }
                if chosen == "@custom" then
                    out[#out + 1] = TextBox(form.speaker, function(text)
                        form.speaker = (string.gsub(E.LineText(text), "[():]", ""))
                        WriteForm(s, form)
                    end, { width = 120, height = 24, placeholder = T("author.montage_builder.scene.voice_name_placeholder") })
                end
                if not form.offstage then
                    local emoteOptions = { { id = "", text = T("author.montage_builder.scene.no_emote") } }
                    for _, e in ipairs(E.SceneEmotes()) do
                        emoteOptions[#emoteOptions + 1] = { id = e, text = e }
                    end
                    out[#out + 1] = PickDropdown(emoteOptions, form.emote or "", function(id)
                        form.emote = cond(id == "", nil, id)
                        WriteForm(s, form)
                    end, { width = 110, tooltip = T("author.montage_builder.scene.emote_tooltip") })
                end
                local langOptions, langChosen = NameOptions(lists.languages, form.lang, { { id = "", text = T("author.montage_builder.scene.any_language") } })
                out[#out + 1] = PickDropdown(langOptions, langChosen or "", function(id)
                    form.lang = cond(id == "", nil, id)
                    WriteForm(s, form)
                end, { width = 140, menuWidth = 200, search = true, tooltip = T("author.montage_builder.scene.language_tooltip") })
                --the pickers on one line, the words on a full-width line below.
                return { gui.Panel{
                    width = "100%-4",
                    height = "auto",
                    flow = "vertical",
                    Row(out, { fit = true, vmargin = 0 }),
                    TextBox(form.text, function(text)
                        form.text = text
                        WriteForm(s, form)
                    end, { width = "100%", height = 24, placeholder = T("author.montage_builder.scene.line_placeholder") }),
                } }, true
            elseif kind == "enter" then
                local options, chosen = NameOptions(lists.monsters, form.monster)
                ---@type Panel[]
                local out = {
                    TextBox(form.name, function(text)
                        RenameCharacter(form.name, text)
                    end, { width = 130, height = 24, placeholder = T("author.montage_builder.scene.character_name_placeholder") }),
                    Word(T("author.montage_builder.scene.played_by")),
                    PickDropdown(options, chosen, function(id)
                        form.monster = id
                        WriteForm(s, form)
                    end, { width = 240, menuWidth = 300, search = true, tooltip = T("author.montage_builder.scene.monster_tooltip") }),
                }
                local found = nil
                pcall(function() found = EncounterMontage.FindMonster(form.monster) end)
                if found == nil then
                    out[#out + 1] = Word(T("author.montage_builder.scene.monster_not_found"), { color = PROBLEM_COLOR })
                end
                return out, false
            elseif kind == "exit" then
                local options, chosen = NameOptions(actorNames, form.name)
                return {
                    PickDropdown(options, chosen, function(id)
                        form.name = id
                        WriteForm(s, form)
                    end, { width = 150, lmargin = 0 }),
                    Word(T("author.montage_builder.scene.leaves_the_stage")),
                }, false
            elseif kind == "emote" then
                local options, chosen = NameOptions(actorNames, form.name, { { id = "PC", text = T("author.montage_builder.scene.who_pc") } })
                local emoteOptions = {}
                for _, e in ipairs(E.SceneEmotes()) do
                    emoteOptions[#emoteOptions + 1] = { id = e, text = e }
                end
                return {
                    PickDropdown(options, chosen, function(id)
                        form.name = id
                        WriteForm(s, form)
                    end, { width = 150, lmargin = 0 }),
                    Word(T("author.montage_builder.scene.emote_is")),
                    PickDropdown(emoteOptions, form.emote, function(id)
                        form.emote = id
                        WriteForm(s, form)
                    end, { width = 110 }),
                    Word(T("author.montage_builder.scene.emote_when")),
                }, false
            elseif kind == "if" or kind == "elseif" then
                return { gui.Panel{ width = "100%-4", height = "auto", flow = "vertical", children = ConditionEditor(s, form, i) } }, true
            elseif kind == "else" then
                return { Word(T("author.montage_builder.scene.else_help"), { hmargin = 0, tmargin = 4 }) }, false
            end
            return { Word(T("author.montage_builder.scene.end_help"), { hmargin = 0, tmargin = 4 }) }, false
        end

        ---@type Panel[]
        local children = { Label(title, { "mbFieldLabel" }) }
        local depth = 0
        for i, step in ipairs(steps) do
            local s = step
            local index = i
            local form = E.ReadSceneStep(s.text, ctx.actors)
            local kind = form.kind
            if kind == "end" or kind == "else" or kind == "elseif" then
                depth = math.max(0, depth - 1)
            end
            local indent = depth * 20
            local style = STEP_STYLE[kind] or STEP_STYLE.narrate

            local insertOptions = {}
            for _, t in ipairs(STEP_TYPES) do
                if t.id ~= "exit" or #actorNames > 0 then
                    insertOptions[#insertOptions + 1] = t
                end
            end
            local tools = {
                gui.Dropdown{
                    classes = { "sizeXs" },
                    width = 34,
                    height = 24,
                    lmargin = 4,
                    valign = "top",
                    textOverride = "+",
                    menuWidth = 200,
                    options = insertOptions,
                    hover = gui.Tooltip(cond(kind == "if" or kind == "elseif" or kind == "else", T("author.montage_builder.scene.add_inside_tooltip"), T("author.montage_builder.scene.add_below_tooltip"))),
                    change = function(element)
                        ---@cast element Dropdown
                        local id = element.idChosen
                        if type(id) == "string" and id ~= "" then
                            InsertAfter(s, id)
                        end
                    end,
                },
            }
            --what "x" removes: a line, a whole branch, or (for an "if") the whole block.
            if kind ~= "end" then
                local last = index
                local what = T("author.montage_builder.status.removed_scene_line")
                local tip = T("author.montage_builder.scene.remove_line_tooltip")
                if kind == "if" then
                    last = E.SceneBlockEnd(texts, index) or index
                    what, tip = T("author.montage_builder.status.removed_branch_block"), T("author.montage_builder.scene.remove_block_tooltip")
                elseif kind == "elseif" or kind == "else" then
                    last = E.SceneBranchEnd(texts, index) or index
                    what, tip = T("author.montage_builder.status.removed_branch"), T("author.montage_builder.scene.remove_branch_tooltip")
                end
                local armed = false
                tools[#tools + 1] = gui.Button{ classes = { "sizeXs" }, width = 26, height = 24, lmargin = 2, valign = "top", text = "x",
                    hover = gui.Tooltip(tip),
                    click = function(element)
                        if kind == "if" and last > index and not armed then
                            armed = true
                            element.text = "?"
                            dmhub.Schedule(3, function()
                                if element.valid then
                                    armed = false
                                    element.text = "x"
                                end
                            end)
                            return
                        end
                        RemoveSteps(index, last, what)
                    end }
            else
                tools[#tools + 1] = gui.Panel{ width = 26, height = 24, lmargin = 2 }
            end

            local formChildren, fills = StepForm(s, form, index)
            local body
            if fills then
                body = gui.Panel{ width = "100%", height = "auto", flow = "horizontal", children = formChildren }
            else
                body = gui.Panel{ width = "auto", height = "auto", halign = "left", flow = "horizontal", children = formChildren }
            end
            children[#children + 1] = Row({
                gui.Label{ fontSize = 11, bold = true, color = style[2], width = 70, height = "auto", valign = "top", tmargin = 5, text = style[1] },
                gui.Panel{ width = indent, height = 1 },
                gui.Panel{
                    width = string.format("100%%-%d", 70 + indent + 66),
                    height = "auto",
                    flow = "vertical",
                    body,
                },
                gui.Panel{ width = "auto", height = "auto", flow = "horizontal", valign = "top", children = tools },
            }, { vmargin = 2 })

            --an "if" grows its block: "else if" and "else" (once).
            if kind == "if" then
                local blockEnd = E.SceneBlockEnd(texts, index)
                if blockEnd ~= nil then
                    local elseAt = nil
                    local d = 0
                    for j = index + 1, blockEnd - 1 do
                        local k = EncounterScript.SceneBranchLine(texts[j])
                        if k == "if" then
                            d = d + 1
                        elseif k == "end" then
                            d = d - 1
                        elseif k == "else" and d == 0 then
                            elseAt = j
                        end
                    end
                    local lead = Lead(s)
                    local function InsertBefore(j, lines, what)
                        Commit(what, One(E.PatchExpanded(parse, steps[j].line, steps[j].line - 1, lines)))
                    end
                    local grow = {
                        SmallButton(T("author.montage_builder.scene.add_else_if"), function()
                            InsertBefore(elseAt or blockEnd, { lead .. "elseif " .. (form.cond or "tier2") .. " then", lead .. INDENT .. "PC looks around." }, T("author.montage_builder.status.added_else_if"))
                        end),
                    }
                    if elseAt == nil then
                        grow[#grow + 1] = SmallButton(T("author.montage_builder.scene.add_else"), function()
                            InsertBefore(blockEnd, { lead .. "else", lead .. INDENT .. "PC looks around." }, T("author.montage_builder.status.added_else"))
                        end)
                    end
                    children[#children + 1] = Row(grow, { fit = true, lmargin = 70 + indent + 54, vmargin = 1 })
                else
                    children[#children + 1] = Row({
                        SmallButton(T("author.montage_builder.scene.add_end"), function()
                            Commit(T("author.montage_builder.status.closed_branch"), One(E.PatchAfter(parse, steps[#steps].line, { Lead(s) .. "end" })))
                        end),
                        Label(T("author.montage_builder.scene.never_closed"), { "mbProblem" }, { width = "auto" }),
                    }, { fit = true, lmargin = 70 + indent, vmargin = 1 })
                end
            end

            if kind == "if" or kind == "else" or kind == "elseif" then
                depth = depth + 1
            end
        end
        if #steps == 0 then
            children[#children + 1] = Label(T("author.montage_builder.scene.no_lines"), { "mbSub" })
        end
        local addOptions = { { id = "", text = T("author.montage_builder.scene.add_step_at_end") } }
        for _, t in ipairs(STEP_TYPES) do
            if t.id ~= "exit" or #actorNames > 0 then
                addOptions[#addOptions + 1] = t
            end
        end
        children[#children + 1] = gui.Dropdown{
            classes = { "sizeXs" },
            width = 240,
            height = 24,
            tmargin = 2,
            options = addOptions,
            idChosen = "",
            change = function(element)
                ---@cast element Dropdown
                local id = element.idChosen
                if type(id) ~= "string" or id == "" then
                    return
                end
                local last = steps[#steps] ~= nil and steps[#steps].line or anchor
                if last == nil then
                    session.status = T("author.montage_builder.status.nowhere_for_line")
                    Refresh()
                    return
                end
                Commit(T("author.montage_builder.status.added_scene_step"), One(E.PatchAfter(parse, last, NewStepLines(id))))
            end,
        }
        children[#children + 1] = Label(cond(ctx.part == "outcome", T("author.montage_builder.scene.help_outcome"), T("author.montage_builder.scene.help")), { "mbSub" })
        return gui.Panel{ classes = { "mbSection" }, children = children }
    end

    --What a scene editor needs to know about its entry: the characters, the
    --options (for "PC chose"), which part of the turn it plays, and every
    --scene list (a character is renamed across all of them).
    local function SceneCtx(entry, part)
        local all = {}
        local function Add(list)
            if list ~= nil then
                all[#all + 1] = list
            end
        end
        Add(entry.sceneLines)
        for _, o in ipairs(entry.options or {}) do
            Add(o.preLines)
            Add(o.postLines)
            for _, k in ipairs(o.knacks or {}) do
                Add(k.preLines)
                Add(k.postLines)
            end
        end
        return { actors = entry.actors or {}, options = entry.options or {}, part = part, allLines = all }
    end

    --- outcomes: free text + rewards and costs ---
    --A tier (or a consequence, a no-roll rule, a table row) as the words
    --the players read plus one row per mechanical clause, each picked from
    --EncounterScript.CLAUSES. `write(text)` stores the new line text;
    --`entry` gives the entry's dice tables and whether it is a threat.

    --The montage's locked entries and every test (option) name, for
    --"Unlock X" and "an edge on X".
    local function MontageNames()
        local locked, options, seenOption = {}, {}, {}
        local function AddOption(name)
            if type(name) == "string" and name ~= "" and not seenOption[lower(name)] then
                seenOption[lower(name)] = true
                options[#options + 1] = name
            end
        end
        for _, b in ipairs(session.parse.beats or {}) do
            for _, e in ipairs(EncounterScript.MontageEntries(b)) do
                if e.locked then
                    locked[#locked + 1] = e.name
                end
                for _, o in ipairs(e.options or {}) do
                    AddOption(o.name)
                end
            end
        end
        for _, d in pairs(session.parse.delves or {}) do
            for _, ob in ipairs(d.obstacles or {}) do
                for _, o in ipairs(ob.options or {}) do
                    AddOption(o.name)
                end
            end
        end
        table.sort(locked)
        table.sort(options)
        return locked, options
    end

    local TARGET_OPTIONS = { { id = "self", text = T("author.montage_builder.outcome.target_self") }, { id = "party", text = T("author.montage_builder.outcome.target_party") } }
    local TEST_EFFECT_OPTIONS = {
        { id = "edge", text = T("author.montage_builder.outcome.test_edge") }, { id = "doubleedge", text = T("author.montage_builder.outcome.test_double_edge") },
        { id = "bane", text = T("author.montage_builder.outcome.test_bane") }, { id = "doublebane", text = T("author.montage_builder.outcome.test_double_bane") },
    }
    local OUTCOME_OPTIONS = {
        { id = "win", text = T("author.montage_builder.outcome.initiative_win") },
        { id = "lose", text = T("author.montage_builder.outcome.initiative_lose") },
        { id = "surprise", text = T("author.montage_builder.outcome.initiative_surprise") },
        { id = "surprised", text = T("author.montage_builder.outcome.initiative_surprised") },
    }
    local CLAUSE_HELP = {
        intelligence = T("author.montage_builder.outcome.help_intelligence"),
        malice = T("author.montage_builder.outcome.help_malice"),
        surges = T("author.montage_builder.outcome.help_surges"),
        loserecovery = T("author.montage_builder.outcome.help_loserecovery"),
        loseconsumable = T("author.montage_builder.outcome.help_loseconsumable"),
        unlock = T("author.montage_builder.outcome.help_unlock"),
        testmod = T("author.montage_builder.outcome.help_testmod"),
        rolltable = T("author.montage_builder.outcome.help_rolltable"),
        revealobject = T("author.montage_builder.outcome.help_revealobject"),
        startzone = T("author.montage_builder.outcome.help_startzone"),
        revealzones = T("author.montage_builder.outcome.help_revealzones"),
        knowstamina = T("author.montage_builder.outcome.help_knowstamina"),
    }

    local function Numbers(lo, hi, current)
        local options = {}
        for n = lo, hi do
            options[#options + 1] = { id = tostring(n), text = tostring(n) }
        end
        if current ~= nil and (current < lo or current > hi) then
            options[#options + 1] = { id = tostring(current), text = tostring(current) }
        end
        return options
    end

    local function OutcomeEditor(text, write, entry, opts)
        opts = opts or {}
        local outcome = E.ReadOutcome(text or "")
        local lists = B.Lists()
        local locked, optionNames = MontageNames()
        local tableNames = {}
        for _, t in pairs((entry and entry.tables) or {}) do
            tableNames[#tableNames + 1] = t.name
        end
        if entry ~= nil and entry.table ~= nil then
            tableNames[#tableNames + 1] = entry.table.name
        end
        table.sort(tableNames)

        local function Write()
            local newText = E.OutcomeText(outcome)
            if newText ~= (text or "") then
                write(newText)
            end
        end

        ---@type Panel[]
        local children = {}
        children[#children + 1] = TextBox(outcome.text, function(newText)
            outcome.text = newText
            Write()
        end, { multiline = true, minHeight = 26, placeholder = opts.placeholder or T("author.montage_builder.outcome.text_placeholder") })

        --one parameter control of an effect row.
        local function ParamControl(effect, param)
            local function Set(field, value)
                effect[field] = value
                effect.text = nil
                Write()
            end
            if param == "target" then
                return PickDropdown(TARGET_OPTIONS, effect.target or "self", function(id) Set("target", id) end, { width = 100 })
            elseif param == "qty" then
                return PickDropdown(Numbers(1, 10, effect.qty), tostring(effect.qty or 1), function(id) Set("qty", tonumber(id)) end, { width = 56 })
            elseif param == "recoveries" then
                local options = Numbers(1, 5, effect.dice == nil and effect.qty or nil)
                options[#options + 1] = { id = "1d3", text = "1d3" }
                options[#options + 1] = { id = "1d6", text = "1d6" }
                return PickDropdown(options, effect.dice or tostring(effect.qty or 1), function(id)
                    if tonumber(id) ~= nil then
                        effect.dice = nil
                        Set("qty", tonumber(id))
                    else
                        Set("dice", id)
                    end
                end, { width = 66, tooltip = T("author.montage_builder.outcome.recoveries_tooltip") })
            elseif param == "item" then
                local resolved = effect.name
                pcall(function()
                    local _, item = EncounterMontage.FindGear(effect.name)
                    if item ~= nil then
                        resolved = item.name
                    end
                end)
                local options, chosen = NameOptions(lists.items, resolved)
                return PickDropdown(options, chosen, function(id) Set("name", id) end, { width = 230, menuWidth = 300, search = true })
            elseif param == "monster" then
                local options, chosen = NameOptions(lists.monsters, effect.name)
                return PickDropdown(options, chosen, function(id) Set("name", id) end, { width = 230, menuWidth = 300, search = true })
            elseif param == "entry" then
                local options, chosen = NameOptions(locked, effect.name)
                return PickDropdown(options, chosen, function(id) Set("name", id) end, { width = 230, menuWidth = 300, tooltip = T("author.montage_builder.outcome.entry_tooltip") })
            elseif param == "option" then
                local options, chosen = NameOptions(optionNames, effect.name)
                return PickDropdown(options, chosen, function(id) Set("name", id) end, { width = 230, menuWidth = 300, search = true })
            elseif param == "table" then
                local options, chosen = NameOptions(tableNames, effect.name)
                return PickDropdown(options, chosen, function(id) Set("name", id) end, { width = 180 })
            elseif param == "testeffect" then
                return PickDropdown(TEST_EFFECT_OPTIONS, effect.effect or "edge", function(id) Set("effect", id) end, { width = 120 })
            elseif param == "outcome" then
                return PickDropdown(OUTCOME_OPTIONS, effect.outcome or "win", function(id) Set("outcome", id) end, { width = 250 })
            elseif param == "damageType" then
                return PickDropdown(NameOptions(lists.damageTypes, effect.damageType), effect.damageType, function(id) Set("damageType", id) end, { width = 110 })
            end
            --keyword / zone / object: a dropdown of what exists, or a text box when there is nothing to list.
            local field = cond(param == "object", "object", cond(param == "zone", "zone", "keyword"))
            local list = cond(param == "object", lists.objects, cond(param == "zone", lists.zones, lists.keywords))
            if #list == 0 then
                return TextBox(effect[field], function(newText) Set(field, E.LineText(newText)) end, { width = 160, height = 24 })
            end
            local options, chosen = NameOptions(list, effect[field])
            return PickDropdown(options, chosen, function(id) Set(field, id) end, { width = 180, menuWidth = 240, search = true })
        end

        local kindOptions = {}
        for _, c in ipairs(EncounterScript.CLAUSES) do
            if c.kind ~= "vanquish" or (entry ~= nil and entry.kind == "threat") then
                kindOptions[#kindOptions + 1] = { id = c.kind, text = string.format("%s: %s", c.group, c.label) }
            end
        end

        for ei, eff in ipairs(outcome.effects) do
            local index = ei
            local effect = eff
            local info = EncounterScript.ClauseInfo(effect.kind)
            ---@type Panel[]
            local row = {
                PickDropdown(kindOptions, effect.kind, function(id)
                    local c = EncounterScript.ClauseInfo(id)
                    if c == nil then
                        return
                    end
                    ---@type table<string, any>
                    --a new kind keeps the line's punctuation and trailing words,
                    --not the words that led into the old clause.
                    local new = { kind = id, hidden = effect.hidden, sep = effect.sep, suffix = effect.suffix }
                    for k, v in pairs(c.defaults) do
                        new[k] = v
                    end
                    --keep who and how many when both kinds take them.
                    for _, p in ipairs(c.params) do
                        if p == "target" and effect.target ~= nil then new.target = effect.target end
                        if p == "qty" and effect.qty ~= nil and effect.dice == nil and effect.kind ~= "rolltable" then new.qty = effect.qty end
                    end
                    if id == "unlock" then new.name = locked[1] or "" end
                    if id == "testmod" then new.name = optionNames[1] or "" end
                    if id == "rolltable" then new.name = tableNames[1] or "" end
                    outcome.effects[index] = new
                    Write()
                end, { width = 230, lmargin = 0, menuWidth = 280 }),
            }
            for _, p in ipairs(info ~= nil and info.params or {}) do
                row[#row + 1] = ParamControl(effect, p)
            end
            row[#row + 1] = PickDropdown({ { id = "shown", text = T("author.montage_builder.outcome.shown") }, { id = "hidden", text = T("author.montage_builder.outcome.hidden") } }, cond(effect.hidden, "hidden", "shown"), function(id)
                effect.hidden = id == "hidden"
                Write()
            end, { width = 84, tooltip = T("author.montage_builder.outcome.hidden_tooltip") })
            row[#row + 1] = gui.Button{ classes = { "sizeXs" }, width = 22, height = 22, lmargin = 4, valign = "center", text = "x",
                hover = gui.Tooltip(T("author.montage_builder.outcome.remove_tooltip")),
                click = function()
                    table.remove(outcome.effects, index)
                    Write()
                end }
            children[#children + 1] = Row(row, { fit = true, vmargin = 1 })
            if CLAUSE_HELP[effect.kind] ~= nil then
                children[#children + 1] = Label(CLAUSE_HELP[effect.kind], { "mbSub" }, { lmargin = 8 })
            end
            if effect.kind == "unlock" and #locked == 0 then
                children[#children + 1] = Label(T("author.montage_builder.outcome.no_locked_entry"), { "mbProblem" })
            elseif effect.kind == "rolltable" and #tableNames == 0 then
                children[#children + 1] = Label(T("author.montage_builder.outcome.no_dice_table"), { "mbProblem" })
            end
        end

        local addOptions = { { id = "", text = T("author.montage_builder.outcome.add") } }
        for _, o in ipairs(kindOptions) do
            addOptions[#addOptions + 1] = o
        end
        children[#children + 1] = gui.Dropdown{
            classes = { "sizeXs" },
            width = 230,
            height = 24,
            tmargin = 1,
            halign = "left",
            options = addOptions,
            idChosen = "",
            menuWidth = 280,
            hasSearch = true,
            change = function(element)
                ---@cast element Dropdown
                local c = EncounterScript.ClauseInfo(element.idChosen)
                if c == nil then
                    return
                end
                ---@type table<string, any>
                local new = { kind = c.kind }
                for k, v in pairs(c.defaults) do
                    new[k] = v
                end
                if c.kind == "unlock" then new.name = locked[1] or "" end
                if c.kind == "testmod" then new.name = optionNames[1] or "" end
                if c.kind == "rolltable" then new.name = tableNames[1] or "" end
                outcome.effects[#outcome.effects + 1] = new
                Write()
            end,
        }
        return gui.Panel{ width = "100%", height = "auto", flow = "vertical", children = children }
    end

    --- dice tables ---
    local function TableEditor(t, title, entry)
        local parse = session.parse
        local children = {}
        children[#children + 1] = Row({
            gui.Label{ classes = { "mbFieldLabel" }, width = "auto", height = "auto", valign = "center", rmargin = 8, text = title or T("author.montage_builder.table.title") },
            TextBox(t.name, function(text)
                Commit(T("author.montage_builder.status.renamed_table"), E.SetLine(parse, t.line, string.format("|%s: %s", trim((string.gsub(E.LineText(text), ":", ""))), t.dice)))
            end, { width = 220, height = 24 }),
            TextBox(t.dice, function(text)
                Commit(T("author.montage_builder.status.changed_table_dice"), E.SetLine(parse, t.line, string.format("|%s: %s", t.name, E.LineText(text))))
            end, { width = 70, height = 24 }),
        }, { fit = true })
        for _, row in ipairs(t.rows or {}) do
            local r = row
            local range = cond(r.lo == r.hi, tostring(r.lo), string.format("%d-%d", r.lo, r.hi))
            children[#children + 1] = Row({
                TextBox(range, function(text)
                    Commit(T("author.montage_builder.status.edited_table_row"), E.SetLine(parse, r.line, string.format("|%s: %s", trim(text), r.text)))
                end, { width = 60, height = 24 }),
                gui.Panel{
                    width = "100%-100",
                    height = "auto",
                    flow = "vertical",
                    OutcomeEditor(r.text, function(text)
                        Commit(T("author.montage_builder.status.edited_table_row"), E.SetLine(parse, r.line, string.format("|%s: %s", range, E.LineText(text))))
                    end, entry, { placeholder = T("author.montage_builder.table.row_placeholder") }),
                },
                gui.Button{ classes = { "sizeXs" }, width = 26, height = 24, lmargin = 4, valign = "top", text = "x",
                    click = function()
                        Commit(T("author.montage_builder.status.removed_table_row"), E.DeleteLine(parse, r.line))
                    end },
            })
        end
        children[#children + 1] = Row({
            SmallButton(T("author.montage_builder.table.add_row"), function()
                local after = t.lastLine or t.line
                local hi = 0
                for _, r in ipairs(t.rows or {}) do hi = math.max(hi, r.hi or 0) end
                Commit(T("author.montage_builder.status.added_table_row"), One(E.PatchAfter(parse, after, { string.format("|%d: +1 hero token", hi + 1) })))
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
                Commit(T("author.montage_builder.status.edited_test"), E.SetRollHeader(parse, roll, name, E.AttrText(newChars, newSkills)))
            end
            children[#children + 1] = Label(T("author.montage_builder.rules.test_label"), { "mbFieldLabel" })
            children[#children + 1] = Row({
                gui.Label{ classes = { "mbSub" }, width = 60, height = "auto", valign = "center", text = T("author.montage_builder.rules.test_name") },
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
                            session.status = T("author.montage_builder.status.test_needs_characteristic")
                            Refresh()
                            return
                        end
                        WriteHeader(roll.name, list, skills)
                    end,
                }
            end
            children[#children + 1] = Row(charChecks, { fit = true })

            --skills: chips with an x, and a dropdown to add one.
            local skillChildren = { gui.Label{ classes = { "mbSub" }, width = 60, height = "auto", valign = "center", text = T("author.montage_builder.rules.skills") } }
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
                    hover = gui.Tooltip(cond(known[lower(s)], T("author.montage_builder.rules.remove_skill_tooltip"), T("author.montage_builder.rules.unknown_skill_tooltip", { skill = s }))),
                    click = function()
                        local list = {}
                        for k, x in ipairs(skills) do
                            if k ~= index then list[#list + 1] = x end
                        end
                        WriteHeader(roll.name, chars, list)
                    end,
                }
            end
            local addOptions = { { id = "", text = T("author.montage_builder.rules.add_skill") } }
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

            --tiers.
            children[#children + 1] = Label(T("author.montage_builder.rules.outcomes_label"), { "mbFieldLabel" })
            for t = 1, 3 do
                local tier = t
                children[#children + 1] = Row({
                    gui.Label{ classes = { "mbSub" }, width = 90, height = "auto", valign = "top", tmargin = 4, text = TIER_RANGES[t] },
                    gui.Panel{
                        width = "100%-96",
                        height = "auto",
                        flow = "vertical",
                        TextBox(roll.teasers[t], function(text)
                            Commit(T("author.montage_builder.status.edited_teaser"), E.SetTier(parse, roll, tier, text, roll.tiers[tier]))
                        end, { placeholder = T("author.montage_builder.rules.teaser_placeholder"), height = 24 }),
                        OutcomeEditor(roll.tiers[t], function(text)
                            Commit(T("author.montage_builder.status.edited_outcome"), E.SetTier(parse, roll, tier, roll.teasers[tier], text))
                        end, entry),
                    },
                })
            end
            --the critical: automatic (tier 3 + a hero token) unless one is written.
            local critChildren = {
                gui.Check{
                    classes = { "sizeXs" },
                    width = 400,
                    height = 24,
                    text = T("author.montage_builder.rules.critical_automatic"),
                    value = roll.critAuto == true,
                    change = function(element)
                        if element.value then
                            Commit(T("author.montage_builder.status.critical_automatic"), E.ClearCritical(parse, roll))
                        else
                            Commit(T("author.montage_builder.status.wrote_critical"), E.SetTier(parse, roll, 4, nil, roll.tiers[4]))
                        end
                    end,
                },
            }
            if not roll.critAuto then
                critChildren[#critChildren + 1] = OutcomeEditor(roll.tiers[4], function(text)
                    Commit(T("author.montage_builder.status.edited_critical"), E.SetTier(parse, roll, 4, roll.teasers[4], text))
                end, entry)
            end
            children[#children + 1] = Row({
                gui.Label{ classes = { "mbSub" }, width = 90, height = "auto", valign = "top", tmargin = 4, text = T("author.montage_builder.rules.critical_label") },
                gui.Panel{
                    width = "100%-96",
                    height = "auto",
                    flow = "vertical",
                    children = critChildren,
                },
            })
        elseif holder.free ~= nil then
            children[#children + 1] = Label(T("author.montage_builder.rules.no_roll_label"), { "mbFieldLabel" })
            local ruleLines = holder.free.lines or {}
            for _, l in ipairs(ruleLines) do
                local lineNo = l
                local docid, at = E.Source(parse, lineNo)
                local raw = E.Split(session.texts[docid] or "").lines[at] or ""
                local lead = string.match(raw, "^(%s*)") or ""
                local ruleText = (string.gsub(raw, "^%s*|", ""))
                local editor = OutcomeEditor(ruleText, function(text)
                    if trim(text) == "" then
                        if #ruleLines > 1 then
                            Commit(T("author.montage_builder.status.removed_rule_line"), E.DeleteLine(parse, lineNo))
                        else
                            session.status = T("author.montage_builder.status.no_roll_needs_rule")
                            Refresh()
                        end
                        return
                    end
                    Commit(T("author.montage_builder.status.edited_rules"), E.SetLine(parse, lineNo, lead .. "|" .. text))
                end, entry)
                if #ruleLines > 1 then
                    children[#children + 1] = Row({
                        gui.Panel{ width = "100%-34", height = "auto", flow = "vertical", editor },
                        gui.Button{ classes = { "sizeXs" }, width = 26, height = 24, lmargin = 4, valign = "top", text = "x",
                            hover = gui.Tooltip(T("author.montage_builder.rules.remove_paragraph_tooltip")),
                            click = function()
                                Commit(T("author.montage_builder.status.removed_rule_line"), E.DeleteLine(parse, lineNo))
                            end },
                    })
                else
                    children[#children + 1] = editor
                end
            end
            if #ruleLines > 0 then
                children[#children + 1] = Row({
                    SmallButton(T("author.montage_builder.rules.add_paragraph"), function()
                        Commit(T("author.montage_builder.status.added_rule_line"), One(E.PatchAfter(parse, ruleLines[#ruleLines], { "|+1 hero token" })))
                    end),
                }, { fit = true })
            end
        end

        --riders (on the roll, or on the option itself).
        local riders = {}
        if roll ~= nil then
            for _, r in ipairs(roll.riders or {}) do riders[#riders + 1] = r end
        end
        for _, r in ipairs(holder.riders or {}) do riders[#riders + 1] = r end
        if roll ~= nil or holder.free ~= nil then
            children[#children + 1] = Label(T("author.montage_builder.rules.knacks_label"), { "mbFieldLabel" })
            local effectOptions = {}
            for _, eff in ipairs(E.RIDER_EFFECTS) do
                effectOptions[#effectOptions + 1] = { id = eff, text = E.RiderWord(eff) }
            end
            local roundOptions = { { id = "any", text = T("author.montage_builder.rules.any_round") } }
            local beat = B.CurrentBeat(session)
            for r = 1, math.max(1, beat ~= nil and #beat.rounds or 1) do
                roundOptions[#roundOptions + 1] = { id = tostring(r), text = T("author.montage_builder.rules.round_option", { number = r }) }
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
                            Commit(T("author.montage_builder.status.edited_knack"), E.SetRider(parse, r, element.idChosen, r.round, r.text))
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
                            Commit(T("author.montage_builder.status.edited_knack"), E.SetRider(parse, r, r.effect, round, r.text))
                        end,
                    },
                    TextBox(r.text, function(text)
                        Commit(T("author.montage_builder.status.edited_knack"), E.SetRider(parse, r, r.effect, r.round, text))
                    end, { width = "100%-300" }),
                    SmallButton(T("author.montage_builder.rules.remove_knack"), function()
                        Commit(T("author.montage_builder.status.removed_knack"), E.RemoveRider(parse, r))
                    end),
                })
                for _, p in ipairs(problems or {}) do
                    children[#children + 1] = Label(p, { "mbProblem" })
                end
            end
            local addRow = {}
            if roll ~= nil then
                addRow[#addRow + 1] = SmallButton(T("author.montage_builder.rules.add_edge"), function()
                    Commit(T("author.montage_builder.status.added_knack"), E.AddRider(parse, session.texts, holder, "edge", nil, "you can climb"))
                end)
                addRow[#addRow + 1] = SmallButton(T("author.montage_builder.rules.add_bane"), function()
                    Commit(T("author.montage_builder.status.added_knack"), E.AddRider(parse, session.texts, holder, "bane", nil, "you have cold weakness"))
                end)
            end
            addRow[#addRow + 1] = SmallButton(T("author.montage_builder.rules.add_secret"), function()
                Commit(T("author.montage_builder.status.added_knack"), E.AddRider(parse, session.texts, holder, "allow", nil, "you are a Dwarf"))
            end)
            children[#children + 1] = Row(addRow, { fit = true })
            children[#children + 1] = Label(T("author.montage_builder.rules.requirements_help"), { "mbSub" })
        end

        --switch between a test and no roll.
        local switch = {}
        if roll ~= nil then
            switch[#switch + 1] = SmallButton(T("author.montage_builder.rules.make_no_roll"), function()
                local block = { "|" .. E.LineText(roll.tiers[2]) }
                for _, r in ipairs(riders) do
                    if r.effect == "allow" then
                        block[#block + 1] = E.RiderLine(r.effect, r.round, r.text)
                    end
                end
                Commit(T("author.montage_builder.status.changed_to_no_roll"), E.SetRules(parse, session.texts, holder, block))
            end)
        elseif holder.free ~= nil or holder.delve == nil then
            switch[#switch + 1] = SmallButton(T("author.montage_builder.rules.make_test"), function()
                local block = DefaultRoll(entry.kind)
                for _, r in ipairs(riders) do
                    block[#block + 1] = E.RiderLine(r.effect, r.round, r.text)
                end
                Commit(T("author.montage_builder.status.changed_to_test"), E.SetRules(parse, session.texts, holder, block))
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
                SmallButton(T("author.montage_builder.text_editor.save"), function()
                    Commit(T("author.montage_builder.status.edited_as_text"), E.ReplaceElement(parse, session.texts, line, level, input.text))
                end),
            }, { fit = true }),
        }
    end

    --- the editor for one knack version ---
    local function KnackEditor(entry, o, k)
        local parse = session.parse
        local children = {}
        children[#children + 1] = Row({
            gui.Label{ classes = { "mbHeading" }, color = "#d9b3ff", width = "auto", height = "auto", valign = "center", rmargin = 8, text = T("author.montage_builder.knack.heading") },
            TextBox(k.requirementText, function(text)
                Commit(T("author.montage_builder.status.edited_knack_version"), E.SetLine(parse, k.line, E.KnackHeadingLine(text)))
            end, { width = 420 }),
        }, { fit = true })
        children[#children + 1] = Label(T("author.montage_builder.knack.help"), { "mbSub" })
        local problems = {}
        pcall(function() problems = EncounterScript.RequirementProblems(k.requirement) end)
        for _, p in ipairs(problems or {}) do
            children[#children + 1] = Label(p, { "mbProblem" })
        end
        if entry.scripted then
            children[#children + 1] = SceneEditor(T("author.montage_builder.knack.scene_before"), k.preLines, k.line, SceneCtx(entry, "option"))
        end
        local switch = RulesEditor(entry, k, children)
        if entry.scripted then
            local anchor = B.RulesEnd(k)
            if anchor ~= nil then
                children[#children + 1] = SceneEditor(T("author.montage_builder.knack.scene_after"), k.postLines, anchor, SceneCtx(entry, "outcome"))
            end
        end
        local tools = {}
        for _, b in ipairs(switch) do tools[#tools + 1] = b end
        tools[#tools + 1] = ConfirmButton(T("author.montage_builder.knack.delete"), function()
            Commit(T("author.montage_builder.status.deleted_knack_version"), E.DeleteElement(parse, session.texts, k.line, 4))
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
            kindText = T("author.montage_builder.option.kind_delve", { delve = o.delve })
        elseif o.roll ~= nil then
            kindText = T("author.montage_builder.option.kind_test")
        elseif o.free ~= nil then
            kindText = T("author.montage_builder.option.kind_no_roll")
        else
            kindText = T("author.montage_builder.option.kind_none")
        end
        local secret = EncounterScript.OptionIsSecret(o)

        children[#children + 1] = Row({
            gui.Label{ classes = { "mbHeading" }, width = 30, text = tostring(optionIndex) .. "." },
            TextBox(o.name, function(text)
                Commit(T("author.montage_builder.status.renamed_option"), E.SetLine(parse, o.line, E.OptionHeadingLine(text)))
            end, { width = 380 }),
            gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", lmargin = 8,
                text = cond(secret, T("author.montage_builder.option.kind_secret", { kind = kindText }), kindText) },
        }, { fit = true })

        if entry.scripted then
            children[#children + 1] = SceneEditor(T("author.montage_builder.option.scene_before"), o.preLines, o.line, SceneCtx(entry, "option"))
        else
            children[#children + 1] = Label(T("author.montage_builder.option.text_label"), { "mbFieldLabel" })
            children[#children + 1] = TextBox(o.text, function(text)
                Commit(T("author.montage_builder.status.edited_option_text"), E.SetProse(parse, session.texts, o.textLines, o.line, text))
            end, { multiline = true, placeholder = T("author.montage_builder.option.text_placeholder") })
        end

        local switch = {}
        if o.delve == nil then
            switch = RulesEditor(entry, o, children)
        end
        if entry.scripted and o.delve == nil then
            local anchor = B.RulesEnd(o)
            if anchor ~= nil then
                children[#children + 1] = SceneEditor(T("author.montage_builder.option.scene_after"), o.postLines, anchor, SceneCtx(entry, "outcome"))
            end
        end

        for _, k in ipairs(o.knacks or {}) do
            children[#children + 1] = KnackEditor(entry, o, k)
        end

        --option tools.
        local textEditor = TextEditorPanel(o.line, 3, T("author.montage_builder.option.text_editor_note"))
        local toolRow = {
            SmallButton(T("author.montage_builder.option.edit_as_text"), function()
                textEditor:SetClass("collapsed", not textEditor:HasClass("collapsed"))
            end),
        }
        for _, b in ipairs(switch) do toolRow[#toolRow + 1] = b end
        if o.delve == nil then
            toolRow[#toolRow + 1] = SmallButton(T("author.montage_builder.option.add_knack_no_roll"), function()
                Commit(T("author.montage_builder.status.added_knack_version"), E.InsertAfterElement(parse, session.texts, o.line, 3,
                    { E.KnackHeadingLine("you can teleport"), "", "|The problem is solved in a blink. +1 hero token" }))
            end)
            toolRow[#toolRow + 1] = SmallButton(T("author.montage_builder.option.add_knack_test"), function()
                local block = { E.KnackHeadingLine("you can fly"), "" }
                for _, l in ipairs(DefaultRoll(entry.kind)) do block[#block + 1] = l end
                Commit(T("author.montage_builder.status.added_knack_version"), E.InsertAfterElement(parse, session.texts, o.line, 3, block))
            end)
        end
        toolRow[#toolRow + 1] = ConfirmButton(T("author.montage_builder.option.delete"), function()
            Commit(T("author.montage_builder.status.deleted_option", { name = tostring(o.name) }), E.DeleteElement(parse, session.texts, o.line, 3))
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
            children[#children + 1] = Label(string.upper(T("author.montage_builder.section.heading", { delve = tostring(entry.delve), name = tostring(entry.name) })), { "mbHeading" }, { color = color })
            children[#children + 1] = SceneEditor(T("author.montage_builder.section.scene"), entry.sceneLines, entry.line, SceneCtx(entry, "intro"))
            if entry.table ~= nil then
                children[#children + 1] = TableEditor(entry.table, T("author.montage_builder.section.treasure_table"), entry)
            elseif entry.section == "chest" then
                children[#children + 1] = Row({
                    SmallButton(T("author.montage_builder.section.add_treasure_table"), function()
                        Commit(T("author.montage_builder.status.added_treasure_table"), E.InsertAfterElement(parse, session.texts, entry.line, 2,
                            E.TableLines{ name = "Treasure", dice = "1d6", rows = { { lo = 1, hi = 3, text = "You gain 1 Healing Potion" }, { lo = 4, hi = 6, text = "+1 hero token" } } }))
                    end),
                }, { fit = true })
            end
            local textEditor = TextEditorPanel(entry.line, 2, T("author.montage_builder.section.text_editor_note"))
            children[#children + 1] = Row({
                SmallButton(T("author.montage_builder.section.edit_as_text"), function() textEditor:SetClass("collapsed", not textEditor:HasClass("collapsed")) end),
                ConfirmButton(T("author.montage_builder.section.delete"), function()
                    session.selected = nil
                    Commit(T("author.montage_builder.status.deleted_section"), E.DeleteElement(parse, session.texts, entry.line, 2))
                end),
            }, { fit = true, tmargin = 8 })
            children[#children + 1] = textEditor
            return children
        end

        children[#children + 1] = Row({
            gui.Label{ classes = { "mbHeading" }, width = "auto", height = "auto", valign = "center", rmargin = 8, color = color,
                text = string.upper(cond(isObstacle, T("author.montage_builder.kind.obstacle"), cond(entry.kind == "threat", T("author.montage_builder.kind.threat"), T("author.montage_builder.kind.opportunity")))) },
            TextBox(entry.name, function(text)
                Do(function() B.RenameEntry(session, entry, text) end)
            end, { width = 320, height = 28 }),
        }, { fit = true })
        children[#children + 1] = Label(T("author.montage_builder.entry.source", { document = B.SourceName(session, entry.line) }), { "mbSub" })

        if not isObstacle then
            local tagRow = {
                gui.Dropdown{
                    classes = { "sizeXs" },
                    width = 130,
                    height = 24,
                    options = { { id = "opportunity", text = T("author.montage_builder.entry.kind_opportunity") }, { id = "threat", text = T("author.montage_builder.entry.kind_threat") } },
                    idChosen = entry.kind,
                    change = function(element)
                        ---@cast element Dropdown
                        Commit(T("author.montage_builder.status.changed_kind"), E.SetEntryHeading(parse, entry, { kind = element.idChosen }))
                    end,
                },
            }
            local tagHelp = {
                required = T("author.montage_builder.entry.required_tooltip"),
                locked = T("author.montage_builder.entry.locked_tooltip"),
                temporary = T("author.montage_builder.entry.temporary_tooltip"),
            }
            for _, tag in ipairs({ "required", "locked", "temporary" }) do
                local key = tag
                tagRow[#tagRow + 1] = gui.Check{
                    classes = { "sizeXs" },
                    fontSize = 14,
                    width = 120,
                    height = 24,
                    lmargin = 8,
                    text = ({ required = T("author.montage_builder.entry.required"), locked = T("author.montage_builder.entry.locked"), temporary = T("author.montage_builder.entry.temporary") })[key],
                    value = entry[key] == true,
                    hover = gui.Tooltip(tagHelp[key]),
                    change = function(element)
                        Commit(T("author.montage_builder.status.changed_tags"), E.SetEntryHeading(parse, entry, { [key] = element.value == true }))
                    end,
                }
            end
            children[#children + 1] = Row(tagRow, { fit = true, tmargin = 4 })
        end

        children[#children + 1] = Label(T("author.montage_builder.entry.card_text_label"), { "mbFieldLabel" })
        children[#children + 1] = TextBox(entry.description, function(text)
            Commit(T("author.montage_builder.status.edited_card_text"), E.SetDescription(parse, session.texts, entry, text))
        end, { multiline = true, placeholder = T("author.montage_builder.entry.card_text_placeholder") })

        children[#children + 1] = Label(T("author.montage_builder.entry.approach_label"), { "mbFieldLabel" })
        children[#children + 1] = TextBox(entry.approach, function(text)
            text = E.LineText(text)
            local block = cond(text == "", {}, { "Options: " .. text })
            if entry.approachLines ~= nil then
                local span = entry.approachLines
                Commit(T("author.montage_builder.status.edited_approach"), One(E.PatchExpanded(parse, span[1][1], span[#span][2], block)))
            elseif #block > 0 then
                local after = entry.line
                if entry.descriptionLines ~= nil then
                    after = entry.descriptionLines[#entry.descriptionLines][2]
                end
                Commit(T("author.montage_builder.status.added_approach"), One(E.InsertBlockAfter(parse, session.texts, after, block)))
            end
        end, { placeholder = T("author.montage_builder.entry.approach_placeholder") })

        if entry.kind == "threat" then
            children[#children + 1] = Label(T("author.montage_builder.entry.consequence_label"), { "mbFieldLabel" })
            children[#children + 1] = OutcomeEditor(entry.consequence ~= nil and entry.consequence.text or "", function(text)
                Commit(T("author.montage_builder.status.edited_consequence"), E.SetConsequence(parse, session.texts, entry, text))
            end, entry, { placeholder = T("author.montage_builder.entry.consequence_placeholder") })
        end

        if entry.scripted then
            children[#children + 1] = SceneEditor(T("author.montage_builder.entry.scene"), entry.sceneLines, entry.sceneSepLine, SceneCtx(entry, "intro"))
        else
            children[#children + 1] = Row({
                SmallButton(T("author.montage_builder.entry.add_scene"), function()
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
                    Commit(T("author.montage_builder.status.added_scene"), One(E.InsertBlockAfter(parse, session.texts, after, { "---", "", "PC approaches." })))
                end),
            }, { fit = true })
            children[#children + 1] = Label(T("author.montage_builder.entry.scene_help"), { "mbSub" })
        end

        for _, t in pairs(entry.tables or {}) do
            children[#children + 1] = TableEditor(t, T("author.montage_builder.table.title"), entry)
        end
        children[#children + 1] = Row({
            SmallButton(T("author.montage_builder.entry.add_dice_table"), function()
                local after = entry.line
                if entry.descriptionLines ~= nil then
                    after = entry.descriptionLines[#entry.descriptionLines][2]
                end
                Commit(T("author.montage_builder.status.added_dice_table"), One(E.InsertBlockAfter(parse, session.texts, after,
                    E.TableLines{ name = "Wares", dice = "1d6", rows = { { lo = 1, hi = 3, text = "You gain 1 Healing Potion" }, { lo = 4, hi = 6, text = "+1 hero token" } } })))
            end),
        }, { fit = true })
        children[#children + 1] = Label(T("author.montage_builder.entry.dice_table_help"), { "mbSub" })

        children[#children + 1] = Label(T("author.montage_builder.entry.options_heading", { count = #entry.options }), { "mbHeading" }, { tmargin = 10 })
        for i, o in ipairs(entry.options) do
            children[#children + 1] = OptionEditor(entry, o, i)
        end
        children[#children + 1] = Row({
            SmallButton(T("author.montage_builder.entry.add_option_test"), function()
                Commit(T("author.montage_builder.status.added_option"), E.InsertAfterElement(parse, session.texts, entry.line, 2,
                    E.OptionBlock("New option", "", DefaultRoll(entry.kind))))
            end),
            SmallButton(T("author.montage_builder.entry.add_option_no_roll"), function()
                Commit(T("author.montage_builder.status.added_option"), E.InsertAfterElement(parse, session.texts, entry.line, 2,
                    E.OptionBlock("New option", "", { "|+1 hero token" })))
            end),
            SmallButton(T("author.montage_builder.entry.add_option_delve"), function()
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
            children[#children + 1] = Label(T("author.montage_builder.entry.problems_heading", { count = #warnings }), { "mbHeading" }, { tmargin = 10, color = PROBLEM_COLOR })
            for _, w in ipairs(warnings) do
                children[#children + 1] = Label(w.message, { "mbProblem" })
            end
        end
        if #textOnly > 0 then
            local quoted = {}
            for _, w in ipairs(textOnly) do
                quoted[#quoted + 1] = string.match(w.message, "'(.-)'") or w.message
            end
            children[#children + 1] = Label(T("author.montage_builder.entry.text_only",
                { count = #textOnly, list = table.concat(quoted, " / ") }), { "mbSub" }, { tmargin = 8 })
        end

        --entry tools.
        local textEditor = TextEditorPanel(entry.line, 2, T("author.montage_builder.entry.text_editor_note"))
        local tools = {
            SmallButton(T("author.montage_builder.entry.edit_as_text"), function()
                textEditor:SetClass("collapsed", not textEditor:HasClass("collapsed"))
            end),
            SmallButton(T("author.montage_builder.entry.open_in_journal"), function()
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
                local moveOptions = { { id = "", text = T("author.montage_builder.entry.move_to_round") } }
                for ri, r in ipairs(beat.rounds) do
                    if ri ~= sel.round then
                        moveOptions[#moveOptions + 1] = { id = tostring(ri), text = T("author.montage_builder.entry.move_round_option", { number = tostring(r.number) }) }
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
            tools[#tools + 1] = ConfirmButton(T("author.montage_builder.entry.delete"), function()
                Do(function() B.DeleteEntry(session, entry) end)
            end)
        else
            tools[#tools + 1] = ConfirmButton(T("author.montage_builder.entry.delete_obstacle"), function()
                session.selected = nil
                Commit(T("author.montage_builder.status.deleted_obstacle"), E.DeleteElement(parse, session.texts, entry.line, 2))
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
        children[#children + 1] = Label(T("author.montage_builder.delve.heading", { name = string.upper(delve.name) }), { "mbHeading" }, { color = OBSTACLE_COLOR })
        children[#children + 1] = Label(T("author.montage_builder.delve.intro", { document = B.SourceName(session, delve.line) }), { "mbSub" })

        children[#children + 1] = gui.Check{
            classes = { "sizeXs" },
            fontSize = 14,
            width = 520,
            height = 24,
            tmargin = 6,
            text = T("author.montage_builder.delve.in_sequence"),
            value = delve.ordered == true,
            change = function(element)
                if element.value then
                    Commit(T("author.montage_builder.status.delve_in_sequence"), One(E.InsertBlockAfter(parse, session.texts, delve.line, { "Order: in sequence" })))
                elseif delve.orderLines ~= nil then
                    Commit(T("author.montage_builder.status.delve_random"), One(E.PatchExpanded(parse, delve.orderLines[1], delve.orderLines[2], {})))
                end
            end,
        }
        if not delve.ordered then
            local function WriteChest(lo, hi)
                lo, hi = tonumber(lo), tonumber(hi)
                if lo == nil or hi == nil or lo < 1 or hi < lo then
                    session.status = T("author.montage_builder.status.chest_interval_invalid")
                    Refresh()
                    return
                end
                local line = cond(lo == hi, string.format("Chest: every %d obstacles", lo), string.format("Chest: every %d-%d obstacles", lo, hi))
                if delve.chestLines ~= nil then
                    Commit(T("author.montage_builder.status.changed_chest_interval"), One(E.PatchExpanded(parse, delve.chestLines[1], delve.chestLines[2], { line })))
                else
                    Commit(T("author.montage_builder.status.set_chest_interval"), One(E.InsertBlockAfter(parse, session.texts, delve.line, { line })))
                end
            end
            children[#children + 1] = Row({
                gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", rmargin = 6, text = T("author.montage_builder.delve.chest_every") },
                TextBox(tostring(delve.chestEvery[1]), function(text) WriteChest(text, delve.chestEvery[2]) end, { width = 40, height = 24 }),
                gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", hmargin = 6, text = T("author.montage_builder.delve.chest_to") },
                TextBox(tostring(delve.chestEvery[2]), function(text) WriteChest(delve.chestEvery[1], text) end, { width = 40, height = 24 }),
                gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", lmargin = 6, text = T("author.montage_builder.delve.chest_obstacles") },
            }, { fit = true, tmargin = 4 })
        end

        children[#children + 1] = Label(T("author.montage_builder.delve.intro_label"), { "mbFieldLabel" })
        children[#children + 1] = TextBox(delve.intro, function(text)
            Commit(T("author.montage_builder.status.edited_delve_intro"), E.SetProse(parse, session.texts, delve.introLines, delve.line, text))
        end, { multiline = true, placeholder = T("author.montage_builder.delve.intro_placeholder") })

        --the sections: which exist, and buttons for the missing ones.
        local SECTIONS = {
            { key = "chest", heading = "Chest", text = "PC pries open a dusty chest.", note = T("author.montage_builder.delve.section_chest_note") },
            { key = "continue", heading = "Continue", text = "PC peers deeper into the dark.", note = T("author.montage_builder.delve.section_continue_note") },
            { key = "leave", heading = "Leave", text = "PC turns back toward the light.", note = T("author.montage_builder.delve.section_leave_note") },
            { key = "forced", heading = "Forced Out", text = "Exhausted, PC staggers out.", note = T("author.montage_builder.delve.section_forced_note") },
            { key = "finish", heading = "End", text = "PC has done it.", note = T("author.montage_builder.delve.section_finish_note") },
        }
        children[#children + 1] = Label(T("author.montage_builder.delve.sections_label"), { "mbFieldLabel" })
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
                Commit(T("author.montage_builder.status.added_section"), E.InsertAfterElement(parse, session.texts, delve.line, 1, block))
            end)
        end
        if #addButtons > 0 then
            children[#children + 1] = Row(addButtons, { fit = true })
        end

        local textEditor = TextEditorPanel(delve.line, 1, T("author.montage_builder.delve.text_editor_note"))
        children[#children + 1] = Row({
            SmallButton(T("author.montage_builder.delve.edit_as_text"), function() textEditor:SetClass("collapsed", not textEditor:HasClass("collapsed")) end),
        }, { fit = true, tmargin = 8 })
        children[#children + 1] = textEditor
        return children
    end

    --- the board ---
    local function EntryCard(entry, selection, isSelected)
        local color = cond(entry.kind == "threat", THREAT_COLOR, cond(entry.kind == "obstacle" or entry.kind == "delvesection", OBSTACLE_COLOR, OPPORTUNITY_COLOR))
        local kindLabel = cond(entry.kind == "delvesection", T("author.montage_builder.card.kind_delve_scene"), string.upper(cond(entry.kind == "obstacle", T("author.montage_builder.kind.obstacle"), cond(entry.kind == "threat", T("author.montage_builder.kind.threat"), T("author.montage_builder.kind.opportunity")))))
        local tags = {}
        if entry.required then tags[#tags + 1] = T("author.montage_builder.card.tag_required") end
        if entry.locked then tags[#tags + 1] = T("author.montage_builder.card.tag_locked") end
        if entry.temporary then tags[#tags + 1] = T("author.montage_builder.card.tag_temporary") end
        local tests, secrets = 0, 0
        for _, o in ipairs(entry.options) do
            if o.roll ~= nil then tests = tests + 1 end
            if EncounterScript.OptionIsSecret(o) then secrets = secrets + 1 end
        end
        local parts = { TP("author.montage_builder.card.options", #entry.options) }
        if entry.kind == "delvesection" then
            parts = { TP("author.montage_builder.card.scene_lines", #(entry.sceneLines or {})) }
            if entry.table ~= nil then parts[#parts + 1] = T("author.montage_builder.card.treasure_table") end
        end
        if secrets > 0 then parts[#parts + 1] = T("author.montage_builder.card.secrets", { count = secrets }) end
        if entry.scripted and entry.kind ~= "delvesection" then parts[#parts + 1] = T("author.montage_builder.card.scene") end
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
                return Label(TP("author.montage_builder.card.problems", #warnings), { "mbProblem" })
            end)(),
        }
    end

    --One "4-5 Players: -1 Opportunity, -1 Threat" line as a form. The line
    --is rewritten whole from the form's values (E.ScalingLine).
    local function PartySizeRow(d)
        local parse = session.parse
        local values = { min = d.min, max = d.max, opportunity = d.removals.opportunity or 0, threat = d.removals.threat or 0 }
        local function Write()
            if values.opportunity + values.threat == 0 then
                session.status = T("author.montage_builder.status.party_size_needs_card")
                Refresh()
                return
            end
            if values.max ~= nil and values.max < values.min then
                values.max = values.min
            end
            Commit(T("author.montage_builder.status.edited_party_size"), E.SetLine(parse, d.line, E.ScalingLine{
                min = values.min, max = values.max,
                removals = { opportunity = values.opportunity, threat = values.threat } }))
        end
        local function Numbers(lo, hi, current, prefix)
            local options = {}
            for n = lo, math.max(hi, current or hi) do
                options[#options + 1] = { id = tostring(n), text = (n > 0 and prefix or "") .. tostring(n) }
            end
            return options
        end
        local function Pick(options, chosen, width, onPick)
            return gui.Dropdown{
                classes = { "sizeXs" },
                width = width,
                height = 24,
                hmargin = 4,
                valign = "center",
                options = options,
                idChosen = chosen,
                change = function(element)
                    ---@cast element Dropdown
                    onPick(element.idChosen)
                end,
            }
        end
        local maxOptions = Numbers(1, 6, d.max)
        maxOptions[#maxOptions + 1] = { id = "+", text = T("author.montage_builder.party_size.or_more") }
        local function Text(text)
            return gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", text = text }
        end
        return gui.Panel{
            classes = { "mbCard" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            Row({
                Text(T("author.montage_builder.party_size.between")),
                Pick(Numbers(1, 6, d.min), tostring(d.min), 52, function(id)
                    values.min = tonumber(id) or values.min
                    Write()
                end),
                Text(T("author.montage_builder.party_size.and")),
                Pick(maxOptions, d.max ~= nil and tostring(d.max) or "+", 86, function(id)
                    values.max = tonumber(id)
                    Write()
                end),
                Text(T("author.montage_builder.party_size.players")),
            }, { fit = true }),
            Row({
                Pick(Numbers(0, 6, values.opportunity, "-"), tostring(values.opportunity), 52, function(id)
                    values.opportunity = tonumber(id) or 0
                    Write()
                end),
                gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", color = OPPORTUNITY_COLOR, text = T("author.montage_builder.party_size.opportunity") },
                Pick(Numbers(0, 6, values.threat, "-"), tostring(values.threat), 52, function(id)
                    values.threat = tonumber(id) or 0
                    Write()
                end),
                gui.Label{ classes = { "mbSub" }, width = "auto", height = "auto", valign = "center", color = THREAT_COLOR, rmargin = 12, text = T("author.montage_builder.party_size.threat") },
                SmallButton(T("author.montage_builder.party_size.remove"), function()
                    Commit(T("author.montage_builder.status.removed_party_size"), E.DeleteLine(parse, d.line))
                end),
            }, { fit = true }),
        }
    end

    local function Board()
        local children = {}
        local beat = B.CurrentBeat(session)
        if beat == nil then
            children[1] = Label(T("author.montage_builder.board.no_montage"), { "mbHeading" })
            return children
        end
        local parse = session.parse

        children[#children + 1] = Label(T("author.montage_builder.board.intro_label"), { "mbFieldLabel" })
        children[#children + 1] = TextBox(beat.intro, function(text)
            Commit(T("author.montage_builder.status.edited_montage_intro"), E.SetProse(parse, session.texts, beat.introLines, beat.line, text))
        end, { multiline = true, placeholder = T("author.montage_builder.board.intro_placeholder") })

        for ri, round in ipairs(beat.rounds) do
            local roundIndex = ri
            children[#children + 1] = Label(cond(round.implicit, T("author.montage_builder.board.round_implicit"), T("author.montage_builder.board.round", { number = tostring(round.number) })), { "mbHeading" }, { tmargin = 12 })
            --party-size trim lines, as forms.
            for _, d in ipairs(round.scaling or {}) do
                children[#children + 1] = PartySizeRow(d)
            end
            if #(round.scaling or {}) > 0 then
                children[#children + 1] = Label(T("author.montage_builder.board.party_size_help"), { "mbSub" })
            end
            local opps, threats = 0, 0
            for _, e in ipairs(round.entries) do
                if e.kind == "threat" then threats = threats + 1 else opps = opps + 1 end
            end
            children[#children + 1] = Label(T("author.montage_builder.board.round_counts", { opportunities = opps, threats = threats }), { "mbSub" })
            if not round.implicit then
                children[#children + 1] = Row({
                    SmallButton(T("author.montage_builder.board.add_party_size"), function()
                        local after = round.line
                        if round.scaling ~= nil and #round.scaling > 0 then
                            after = round.scaling[#round.scaling].line
                        end
                        local patch, why = E.PatchAfter(parse, after, { E.ScalingLine{ min = 4, max = 4, removals = { opportunity = 1 } } })
                        Commit(T("author.montage_builder.status.added_party_size"), patch ~= nil and { patch } or nil, why)
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
                SmallButton(T("author.montage_builder.board.add_opportunity"), function() Do(function() B.AddEntry(session, roundIndex, "opportunity") end) end),
                SmallButton(T("author.montage_builder.board.add_threat"), function() Do(function() B.AddEntry(session, roundIndex, "threat") end) end),
            }, { fit = true })
        end
        children[#children + 1] = Row({
            SmallButton(T("author.montage_builder.board.add_round"), function() Do(function() B.AddRound(session) end) end),
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
                Label(T("author.montage_builder.board.delve_heading", { name = delve.name }), { "mbHeading" }, { color = OBSTACLE_COLOR, bmargin = 0 }),
                Label(cond(delve.ordered, T("author.montage_builder.board.delve_summary_sequence", { obstacles = TP("author.montage_builder.board.delve_obstacles", #delve.obstacles) }),
                    T("author.montage_builder.board.delve_summary_random", { obstacles = TP("author.montage_builder.board.delve_obstacles", #delve.obstacles), low = delve.chestEvery[1], high = delve.chestEvery[2] })), { "mbSub" }),
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
                SmallButton(T("author.montage_builder.board.add_obstacle"), function() Do(function() B.AddObstacle(session, key) end) end),
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
        return cond(n == 0, T("author.montage_builder.footer.no_problems"), TP("author.montage_builder.footer.problems", n))
    end

    --What the script view (EncounterScriptBuilder.lua) builds with: this
    --window's session and edits, and its shared form pieces.
    local backButton, testButton
    local ctx = {
        session = session,
        Commit = Commit,
        Do = Do,
        Refresh = function() Refresh() end,
        OutcomeEditor = OutcomeEditor,
        PickDropdown = PickDropdown,
        NameOptions = NameOptions,
        Word = Word,
        TextBox = TextBox,
        Label = Label,
        Row = Row,
        SmallButton = SmallButton,
        ConfirmButton = ConfirmButton,
        close = close,
        --show the editor's top (1 is the top of a vscroll).
        ScrollEditorTop = function()
            if editorPanel ~= nil and editorPanel.valid then
                editorPanel.vscrollPosition = 1
            end
        end,
        --switch to the montage board for the montage beat `beat`.
        OpenMontage = function(beat)
            for i, m in ipairs(session.montages) do
                if m.beat.line == beat.line then
                    session.beatIndex = i
                end
            end
            session.view = "montage"
            session.selected = nil
            Refresh()
            if editorPanel ~= nil and editorPanel.valid then
                editorPanel.vscrollPosition = 1
            end
            if boardPanel ~= nil and boardPanel.valid then
                boardPanel.vscrollPosition = 1
            end
        end,
    }

    Refresh = function()
        if boardBody == nil or not boardBody.valid then
            return
        end
        local scriptView = session.view == "script"
        local ok, children
        if scriptView then
            ok, children = pcall(EncounterScriptBuilder.Outline, ctx)
        else
            ok, children = pcall(Board)
        end
        if not ok then
            children = { Label(T("author.montage_builder.window.board_failed", { error = tostring(children) }), { "mbProblem" }) }
        end
        boardBody.children = children

        local entry = B.SelectedEntry(session)
        local editorChildren
        local sel = session.selected
        local selectedDelve = sel ~= nil and sel.kind == "delve" and session.parse.delves[sel.delve] or nil
        if scriptView then
            local okScript, built = pcall(EncounterScriptBuilder.Editor, ctx)
            if okScript then
                editorChildren = built
            else
                editorChildren = { Label(T("author.montage_builder.window.editor_failed", { error = tostring(built) }), { "mbProblem" }) }
            end
        elseif selectedDelve ~= nil then
            local okDelve, built = pcall(DelveEditor, selectedDelve)
            if okDelve then
                editorChildren = built
            else
                editorChildren = { Label(T("author.montage_builder.window.editor_failed", { error = tostring(built) }), { "mbProblem" }) }
            end
        elseif entry == nil then
            editorChildren = {
                Label(T("author.montage_builder.window.empty_heading"), { "mbHeading" }),
                Label(T("author.montage_builder.window.empty_help"), { "mbSub" }),
            }
        else
            local okEditor, built = pcall(EntryEditor, entry)
            if okEditor then
                editorChildren = built
            else
                editorChildren = { Label(T("author.montage_builder.window.editor_failed", { error = tostring(built) }), { "mbProblem" }) }
            end
        end
        editorBody.children = editorChildren
        statusLabel.text = (session.status ~= "" and (session.status .. "   ") or "") .. ProblemsFooterText()
        titleLabel.text = cond(scriptView, T("author.encounter_builder.window.title", { name = tostring(session.names[session.rootId]) }), T("author.montage_builder.window.title", { name = tostring(session.names[session.rootId]) }))
        if beatDropdown ~= nil then
            local options = {}
            for i, m in ipairs(session.montages) do
                options[#options + 1] = { id = tostring(i), text = T("author.montage_builder.window.montage_option", { number = i, beat = m.index }) }
            end
            beatDropdown.options = options
            beatDropdown.idChosen = tostring(session.beatIndex)
            beatDropdown:SetClass("collapsed", scriptView or #options < 2)
        end
        if backButton ~= nil and backButton.valid then
            backButton:SetClass("collapsed", scriptView)
        end
        if testButton ~= nil and testButton.valid then
            testButton:SetClass("collapsed", scriptView)
        end
    end

    titleLabel = gui.Label{ classes = { "sizeXl", "bold" }, width = "auto", height = "auto", halign = "left", valign = "center", text = T("author.montage_builder.window.title_initial") }
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
    backButton = SmallButton(T("author.montage_builder.window.back_to_script"), function()
        session.view = "script"
        Refresh()
        if boardPanel ~= nil and boardPanel.valid then
            boardPanel.vscrollPosition = 1
        end
    end)
    testButton = SmallButton(T("author.montage_builder.window.test_montage"), function()
        close()
        pcall(function() EncounterTest.ShowDialog("montage") end)
    end)

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
                    backButton,
                    SmallButton(T("author.montage_builder.window.undo"), function() Do(function() B.Undo(session) end) end),
                    testButton,
                    SmallButton(T("author.montage_builder.window.validator"), function()
                        close()
                        pcall(function() DockablePanel.ShowPanelByName(EncounterScriptValidator.panelName) end)
                    end),
                    SmallButton(T("author.montage_builder.window.close"), function() close() end),
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

--Show the builder for `session` ("script": the whole script; "montage":
--the montage board).
local function ShowWindow(session, view)
    local gamehud = GameHud.instance
    if not gamehud then
        return
    end
    session.view = view or "montage"
    B.session = session
    B._lists = nil
    local window = B.CreateWindow(session, function()
        gamehud:CloseModal()
    end)
    gamehud:ShowModal(window)
end

--A map with no script: offer to write one, filed under the map.
local function OfferNewScript()
    local gamehud = GameHud.instance
    if not gamehud then
        return
    end
    local dialog
    dialog = gui.Panel{
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "#000000a0",
        styles = ThemeEngine.MergeStyles(STYLES),
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function()
            gamehud:CloseModal()
        end,
        gui.Panel{
            classes = { "framedPanel" },
            width = 560,
            height = "auto",
            halign = "center",
            valign = "center",
            flow = "vertical",
            pad = 20,
            borderBox = true,
            Label(T("author.encounter_builder.new_script.heading"), { "mbHeading" }),
            Label(T("author.encounter_builder.new_script.help"), { "mbSub" }),
            Row({
                SmallButton(T("author.encounter_builder.new_script.create"), function()
                    gamehud:CloseModal()
                    local lines = { "Encounter script for this map." , "" }
                    for _, block in ipairs({ E.NarrativeBeatBlock(), E.MontageBeatBlock(), E.EncounterBeatBlock(),
                        E.StoryBlock("Town Gate", "Why the heroes have come here."),
                        E.StoryBlock("Conclusion", "What the heroes' victory means."),
                        E.StoryBlock("Defeat", "What the heroes' defeat means.") }) do
                        for _, l in ipairs(block) do
                            lines[#lines + 1] = l
                        end
                        lines[#lines + 1] = ""
                    end
                    local id = dmhub.GenerateGuid()
                    local doc = MarkdownDocument.new{
                        id = id,
                        description = "Encounter Script",
                        parentFolder = game.currentMapId,
                        annotations = {},
                    }
                    doc:SetTextContent(table.concat(lines, "\n"))
                    doc:Upload()
                    local session = B.Load(id, doc)
                    if session ~= nil then
                        session.status = T("author.encounter_builder.new_script.created", { document = doc.description })
                        ShowWindow(session, "script")
                    end
                end),
                SmallButton(T("author.encounter_builder.new_script.cancel"), function() gamehud:CloseModal() end),
            }, { fit = true, tmargin = 10 }),
        },
    }
    gamehud:ShowModal(dialog)
end

--Open the builder on the current map's script. `view` is "script" (the
--Encounter Builder) or "montage" (the Montage Builder, the default).
function B.Open(docid, view)
    if not dmhub.isDM then
        print("Encounter Builder: only the Director can edit the encounter script.")
        return
    end
    local session, why = B.Load(docid)
    if session == nil then
        if docid == nil and view == "script" then
            OfferNewScript()
            return
        end
        print("Montage Builder: " .. tostring(why))
        return
    end
    ShowWindow(session, view)
end

Commands.Register{
    name = "Encounter Builder",
    identifier = "eotwencounterbuilder",
    icon = "panels/initiative/initiative-icon.png",
    menu = "game",
    group = "eotwtest",
    execute = function()
        B.Open(nil, "script")
    end,
    filtered = function()
        return not dmhub.isDM
    end,
}

pcall(function()
    Commands.RegisterMacro{
        name = "eotwbuilder",
        summary = "open the Encounter of the Week Montage Builder",
        doc = "Usage: /eotwbuilder\nOpens the Montage Builder on the current map's Encounter of the Week script: the montage's rounds and entries on a board, and an editor for each entry. Changes are written straight into the script's journal documents. Game > Encounter Builder opens the whole script.",
        command = function()
            B.Open(nil, "montage")
        end,
    }
    Commands.RegisterMacro{
        name = "eotwencounter",
        summary = "open the Encounter of the Week Encounter Builder",
        doc = "Usage: /eotwencounter\nOpens the Encounter Builder on the current map's Encounter of the Week script: its beats in order (narratives, montages, the encounter), the story screens and the optional features, each with a form. A map with no script is offered a new one.",
        command = function()
            B.Open(nil, "script")
        end,
    }
end)
