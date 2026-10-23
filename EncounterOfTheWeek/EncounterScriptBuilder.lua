local mod = dmhub.GetModLoading()

--Encounter of the Week: the Encounter Builder.
--
--The whole-script view of the builder window (EncounterMontageBuilder.lua
--owns the window, the session, the undo stack and the shared form pieces;
--this file draws its "script" view). It shows the script as an author thinks
--of it: the optional features it turns on, the Town Gate text, the beats in
--the order they play (narratives, montages, the encounter) and the
--Conclusion / Defeat screens. Each has a form; a montage opens the Montage
--Builder. As everywhere in the builder, the markdown stays the source of
--truth: every change is a line patch on the document the text came from.
--Design: EncounterOfTheWeek.md, "The Encounter Builder".
--
--Every function takes `ctx`, the window's toolkit (see "What the script
--view builds with" in EncounterMontageBuilder.lua): session, Commit, Do,
--Refresh, OutcomeEditor, PickDropdown, NameOptions, Word, TextBox, Label,
--Row, SmallButton, ConfirmButton, close, ScrollEditorTop, OpenMontage.

EncounterScriptBuilder = {}
local S = EncounterScriptBuilder
local E = EncounterScriptEdit

local T = UIText.T
local TP = UIText.Plural

local KIND_COLOR = {
    narrative = "#7fb7d9",
    montage = "#6fae7a",
    encounter = "#c46a6a",
    story = "#c9a96a",
    features = "#d9b3ff",
}
local PROBLEM_COLOR = "#e88a8a"
local ON_COLOR = "#7fd97f"

--The story screens, in the order they are seen.
local STORY = {
    towngate = { key = "towngate", title = "Town Gate", note = T("author.script_builder.story.towngate_note"),
        starter = "Why the heroes have come here." },
    conclusion = { key = "conclusion", title = "Conclusion", note = T("author.script_builder.story.conclusion_note"),
        starter = "What the heroes' victory means." },
    defeat = { key = "defeat", title = "Defeat", note = T("author.script_builder.story.defeat_note"),
        starter = "What the heroes' defeat means." },
}

local function trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function lower(s)
    return string.lower(s or "")
end

--A patch (or nil + why) as a list for Commit.
local function One(patch, why)
    if patch == nil then
        return nil, why
    end
    return { patch }
end

local function DocsTable()
    return dmhub.GetTable("documents") or {}
end

--A narrative scene's written choices. A scene with none gets an implicit
--"Proceed" from the parser, which has no line of its own to edit.
local function RealOptions(section)
    local result = {}
    for _, o in ipairs(section.options or {}) do
        if not o.implicit then
            result[#result + 1] = o
        end
    end
    return result
end

--What a beat's kind is called in its small tag on the outline.
local function BeatKindName(kind)
    if kind == "narrative" then
        return T("author.script_builder.outline.kind_narrative")
    elseif kind == "montage" then
        return T("author.script_builder.outline.kind_montage")
    elseif kind == "encounter" then
        return T("author.script_builder.outline.kind_encounter")
    end
    return kind
end

--- reading the script ----------------------------------------------------------------

--What a beat is called on the outline: a narrative by its first scene.
function S.BeatLabel(beat)
    if beat.kind == "narrative" then
        local first = beat.sections ~= nil and beat.sections[1] or nil
        if first ~= nil then
            return T("author.script_builder.beat.label_narrative_scene", { scene = first.name })
        end
        return T("author.script_builder.beat.label_narrative")
    elseif beat.kind == "montage" then
        return T("author.script_builder.beat.label_montage")
    elseif beat.kind == "encounter" then
        return T("author.script_builder.beat.label_encounter")
    end
    return beat.title or T("author.script_builder.beat.label_other")
end

--One line saying what is in a beat.
function S.BeatSummary(beat)
    if beat.kind == "narrative" then
        local options = 0
        for _, s in ipairs(beat.sections or {}) do
            options = options + #RealOptions(s)
        end
        return T("author.script_builder.beat.summary_narrative", { scenes = TP("author.script_builder.beat.scenes", #(beat.sections or {})),
            choices = TP("author.script_builder.beat.choices", options) })
    elseif beat.kind == "montage" then
        local entries = 0
        for _, r in ipairs(beat.rounds or {}) do
            entries = entries + #(r.entries or {})
        end
        return T("author.script_builder.beat.summary_montage", { rounds = TP("author.script_builder.beat.rounds", #(beat.rounds or {})),
            entries = TP("author.script_builder.beat.entries", entries) })
    elseif beat.kind == "encounter" then
        local parts = { cond(beat.encounterTag ~= nil, T("author.script_builder.beat.monsters_placed"), T("author.script_builder.beat.no_monsters")) }
        if #(beat.setup or {}) > 0 then
            parts[#parts + 1] = TP("author.script_builder.beat.setup_lines", #beat.setup)
        end
        if #(beat.reinforcements or {}) > 0 then
            parts[#parts + 1] = TP("author.script_builder.beat.reinforcement_groups", #beat.reinforcements)
        end
        return table.concat(parts, ", ")
    end
    return ""
end

--Where each beat sits in the master document: { [beatIndex] = { first,
--last, shared } } in master lines. A beat written in an included document
--sits at its include link; `shared` when one link brings in several
--top-level sections (it cannot be moved or deleted on its own here).
function S.RootSpans(session)
    local parse = session.parse
    local lines = E.Split(session.texts[session.rootId] or "").lines
    local elements = {}
    for i, b in ipairs(parse.beats or {}) do
        if (b.line or 0) > 0 then
            elements[#elements + 1] = { beat = i, line = b.line }
        end
    end
    for _, st in pairs(parse.story or {}) do
        elements[#elements + 1] = { line = st.line }
    end
    for _, d in pairs(parse.delves or {}) do
        elements[#elements + 1] = { line = d.line }
    end
    if parse.part ~= nil then
        elements[#elements + 1] = { line = parse.part.line }
    end
    local starts, count = {}, {}
    for _, el in ipairs(elements) do
        el.root = E.RootLine(parse, el.line)
        if el.root ~= nil then
            if count[el.root] == nil then
                starts[#starts + 1] = el.root
            end
            count[el.root] = (count[el.root] or 0) + 1
        end
    end
    table.sort(starts)
    local spans = {}
    for _, el in ipairs(elements) do
        if el.beat ~= nil and el.root ~= nil then
            local last = #lines
            for _, st in ipairs(starts) do
                if st > el.root then
                    last = st - 1
                    break
                end
            end
            while last > el.root and trim(lines[last]) == "" do
                last = last - 1
            end
            spans[el.beat] = { first = el.root, last = last, shared = count[el.root] > 1 }
        end
    end
    return spans
end

--The last non-blank line of the master document.
local function LastTextLine(session)
    local lines = E.Split(session.texts[session.rootId] or "").lines
    local last = #lines
    while last > 0 and trim(lines[last]) == "" do
        last = last - 1
    end
    return last
end

--Every "Unlock: <feature>" in the script: { { feature, line, beat, section } }.
function S.Unlocks(session)
    local result = {}
    for _, b in ipairs(session.parse.beats or {}) do
        for _, u in ipairs(b.unlocks or {}) do
            result[#result + 1] = { feature = u.feature, line = u.line, beat = b }
        end
        for _, sec in ipairs(b.sections or {}) do
            for _, u in ipairs(sec.unlocks or {}) do
                result[#result + 1] = { feature = u.feature, line = u.line, beat = b, section = sec }
            end
        end
    end
    return result
end

--How many outcomes in the script grant Intelligence.
function S.IntelligenceGrants(session)
    local n = 0
    local function Scan(effects)
        for _, e in ipairs(effects or {}) do
            if e.kind == "intelligence" then
                n = n + 1
            end
        end
    end
    for _, b in ipairs(session.parse.beats or {}) do
        for _, sec in ipairs(b.sections or {}) do
            for _, o in ipairs(sec.options or {}) do
                Scan(o.effects)
            end
        end
        for _, e in ipairs(EncounterScript.MontageEntries(b)) do
            if e.consequence ~= nil then
                Scan(e.consequence.effects)
            end
            for _, o in ipairs(e.options or {}) do
                for _, effects in ipairs(EncounterScript.OptionEffectLists(o)) do
                    Scan(effects)
                end
            end
        end
    end
    return n
end

--Parser notes the builder shows as a choice rather than a problem: the
--form already says it ("Enter: where their group was placed").
local NOT_PROBLEMS = { "have no 'Enter:' zone" }

--Problems (not text-only notes) inside the element headed at `line`.
local function Problems(session, line, level)
    local result = {}
    for _, w in ipairs(EncounterMontageBuilder.WarningsIn(session, line, level)) do
        local note = w.textOnly
        for _, pattern in ipairs(NOT_PROBLEMS) do
            if string.find(w.message or "", pattern, 1, true) ~= nil then
                note = true
            end
        end
        if not note then
            result[#result + 1] = w
        end
    end
    return result
end

--- changing the script's structure ---------------------------------------------------

--Move beat `index` up (-1) or down (+1) past its neighbour.
function S.MoveBeat(ctx, index, dir)
    local session = ctx.session
    local beats = session.parse.beats
    local other = index + dir
    if beats[index] == nil or beats[other] == nil then
        return
    end
    local spans = S.RootSpans(session)
    local a, b = spans[math.min(index, other)], spans[math.max(index, other)]
    if a == nil or b == nil or a.shared or b.shared then
        session.status = T("author.script_builder.status.not_moved_shared")
        ctx.Refresh()
        return
    end
    local lines = E.Split(session.texts[session.rootId]).lines
    local swapped, map = E.SwapBlocks(lines, a.first, a.last, b.first, b.last)
    local region = {}
    for l = a.first, b.last do
        region[#region + 1] = swapped[l]
    end
    local ok, changed = pcall(E.Apply, session.texts, { E.Patch(session.rootId, a.first, b.last, region) })
    if not ok then
        session.status = T("author.script_builder.status.not_moved", { why = tostring(changed) })
        ctx.Refresh()
        return
    end
    ctx.Do(function()
        if EncounterMontageBuilder.CommitTexts(session, cond(dir < 0, T("author.script_builder.status.moved_earlier", { beat = S.BeatLabel(beats[index]) }), T("author.script_builder.status.moved_later", { beat = S.BeatLabel(beats[index]) })),
            changed, { [session.rootId] = map }) then
            session.scriptSelected = { kind = "beat", index = other }
        end
    end)
end

--Delete beat `index` (with the blank lines after it).
function S.DeleteBeat(ctx, index)
    local session = ctx.session
    local beat = session.parse.beats[index]
    local span = S.RootSpans(session)[index]
    if beat == nil or span == nil then
        return
    end
    if span.shared then
        session.status = T("author.script_builder.status.not_deleted_shared")
        ctx.Refresh()
        return
    end
    local lines = E.Split(session.texts[session.rootId]).lines
    local last = span.last
    while last < #lines and trim(lines[last + 1]) == "" do
        last = last + 1
    end
    session.scriptSelected = nil
    ctx.Commit(T("author.script_builder.status.deleted_beat", { beat = S.BeatLabel(beat) }), { E.Patch(session.rootId, span.first, last, {}) }, nil, { keepTags = true })
end

--Add a new beat of `kind`: a narrative or montage goes in front of the
--encounter (the fight comes last), an encounter at the end.
function S.AddBeat(ctx, kind)
    local session = ctx.session
    local beats = session.parse.beats or {}
    local spans = S.RootSpans(session)
    local encounterIndex = nil
    for i, b in ipairs(beats) do
        if b.kind == "encounter" and spans[i] ~= nil then
            encounterIndex = i
        end
    end
    local anchor = nil
    if kind ~= "encounter" and encounterIndex ~= nil then
        anchor = spans[encounterIndex].first - 1
        --insert after the blank line(s) above the encounter, not between them.
        local lines = E.Split(session.texts[session.rootId]).lines
        while anchor > 0 and trim(lines[anchor]) == "" do
            anchor = anchor - 1
        end
    else
        for i = #beats, 1, -1 do
            if spans[i] ~= nil then
                anchor = spans[i].last
                break
            end
        end
        anchor = anchor or LastTextLine(session)
    end
    local block = kind == "narrative" and E.NarrativeBeatBlock() or (kind == "montage" and E.MontageBeatBlock() or E.EncounterBeatBlock())
    local patch = E.InsertBlockAfterDocLine(session.texts, session.rootId, anchor, block)
    local before = #beats
    ctx.Do(function()
        if EncounterMontageBuilder.Commit(session, (kind == "narrative" and T("author.script_builder.status.added_narrative") or (kind == "montage" and T("author.script_builder.status.added_montage") or T("author.script_builder.status.added_encounter"))), { patch }, nil, { keepTags = true }) then
            --select the new beat: the first of that kind starting below the anchor.
            local newBeats = session.parse.beats
            local newSpans = S.RootSpans(session)
            local best = nil
            for i, b in ipairs(newBeats) do
                local span = newSpans[i]
                if b.kind == kind and span ~= nil and span.first > anchor and (best == nil or span.first < newSpans[best].first) then
                    best = i
                end
            end
            if best ~= nil then
                session.scriptSelected = { kind = "beat", index = best }
            end
            if #newBeats <= before then
                session.status = T("author.script_builder.status.added_unparsed")
            end
        end
    end)
    ctx.ScrollEditorTop()
end

--Add a story screen (Town Gate, Conclusion, Defeat) at the end of the master.
function S.AddStory(ctx, key)
    local session = ctx.session
    local info = STORY[key]
    local patch = E.InsertBlockAfterDocLine(session.texts, session.rootId, LastTextLine(session), E.StoryBlock(info.title, info.starter))
    session.scriptSelected = { kind = "story", key = key }
    ctx.Commit(T("author.script_builder.status.added_story", { title = info.title }), { patch }, nil, { keepTags = true })
end

--Turn a feature on (an "Unlock:" line in the first narrative beat, made if
--there is none) or off (every "Unlock:" line for it goes).
function S.SetFeature(ctx, feature, on)
    local session = ctx.session
    local parse = session.parse
    if not on then
        local patches = {}
        for _, u in ipairs(S.Unlocks(session)) do
            if u.feature == feature.key then
                local p = E.PatchExpanded(parse, u.line, u.line, {})
                if p ~= nil then
                    patches[#patches + 1] = p
                end
            end
        end
        ctx.Commit(T("author.script_builder.status.feature_off", { feature = feature.name }), patches)
        return
    end
    for _, b in ipairs(parse.beats or {}) do
        if b.kind == "narrative" then
            local after = b.line
            for _, span in ipairs(b.introLines or {}) do
                after = math.max(after, span[2])
            end
            ctx.Commit(T("author.script_builder.status.feature_on", { feature = feature.name }),
                One(E.InsertBlockAfter(parse, session.texts, after, { E.UnlockLine(feature.name) })))
            return
        end
    end
    --no narrative yet: one at the start, which unlocks it as the game opens.
    local spans = S.RootSpans(session)
    local anchor = spans[1] ~= nil and spans[1].first - 1 or LastTextLine(session)
    local lines = E.Split(session.texts[session.rootId]).lines
    while anchor > 0 and trim(lines[anchor]) == "" do
        anchor = anchor - 1
    end
    local block = { "# Narrative", "", "The heroes prepare for what lies ahead.", "", E.UnlockLine(feature.name), "",
        "## Preparations", "", "Describe the scene." }
    ctx.Commit(T("author.script_builder.status.feature_on_new_narrative", { feature = feature.name }),
        { E.InsertBlockAfterDocLine(session.texts, session.rootId, anchor, block) }, nil, { keepTags = true })
end

--- the outline (left) ------------------------------------------------------------------

local function Card(ctx, selection, color, kindText, title, sub, problems, tools)
    local session = ctx.session
    local s = session.scriptSelected
    local isSelected = s ~= nil and s.kind == selection.kind and s.index == selection.index and s.key == selection.key
    ---@type Panel[]
    local children = {
        ctx.Row({
            gui.Label{ fontSize = 11, bold = true, color = color, width = "auto", height = "auto", valign = "center", rmargin = 6, text = kindText },
            gui.Label{ fontSize = 15, bold = true, width = "100%-170", height = "auto", textWrap = true, text = title },
            gui.Panel{ width = "auto", height = "auto", halign = "right", flow = "horizontal", children = tools or {} },
        }),
    }
    if sub ~= nil and sub ~= "" then
        children[#children + 1] = ctx.Label(sub, { "mbSub" })
    end
    if problems ~= nil and problems > 0 then
        children[#children + 1] = ctx.Label(TP("author.script_builder.outline.problems", problems), { "mbProblem" })
    end
    return gui.Panel{
        classes = { "mbCard", cond(isSelected, "selected", nil) },
        borderColor = cond(isSelected, nil, color),
        children = children,
        click = function()
            session.scriptSelected = selection
            ctx.Refresh()
            ctx.ScrollEditorTop()
        end,
    }
end

local function TinyButton(text, tooltip, onClick)
    return gui.Button{
        classes = { "sizeXs" },
        width = 24,
        height = 22,
        lmargin = 2,
        text = text,
        hover = gui.Tooltip(tooltip),
        click = function()
            onClick()
        end,
    }
end

function S.Outline(ctx)
    local session = ctx.session
    local parse = session.parse
    local children = {}

    if parse.part ~= nil then
        children[#children + 1] = ctx.Label((parse.part.title ~= nil and T("author.script_builder.outline.series_part_titled", { number = parse.part.number, title = parse.part.title })
            or T("author.script_builder.outline.series_part", { number = parse.part.number })), { "mbSub" })
    end

    --optional features.
    local unlocked = EncounterScript.UnlockedFeatures(parse)
    local featureNames = {}
    for _, f in pairs(EncounterScript.FEATURES) do
        featureNames[#featureNames + 1] = cond(unlocked[f.key], T("author.script_builder.outline.feature_on", { feature = f.name }), T("author.script_builder.outline.feature_off", { feature = f.name }))
    end
    table.sort(featureNames)
    children[#children + 1] = Card(ctx, { kind = "features" }, KIND_COLOR.features, T("author.script_builder.outline.features_kind"), T("author.script_builder.outline.features_title"),
        table.concat(featureNames, "  |  "), 0, {})

    --before the adventure.
    children[#children + 1] = ctx.Label(T("author.script_builder.outline.before_heading"), { "mbHeading" }, { tmargin = 10 })
    local story = parse.story or {}
    if story.towngate ~= nil then
        children[#children + 1] = Card(ctx, { kind = "story", key = "towngate" }, KIND_COLOR.story, T("author.script_builder.outline.story_kind"), STORY.towngate.title,
            string.sub(story.towngate.text or "", 1, 80), #Problems(session, story.towngate.line, 1), {})
    else
        children[#children + 1] = ctx.Row({ ctx.SmallButton(T("author.script_builder.outline.add_story", { title = STORY.towngate.title }), function() ctx.Do(function() S.AddStory(ctx, "towngate") end) end) }, { fit = true })
    end

    --the beats, in the order they play.
    children[#children + 1] = ctx.Label(T("author.script_builder.outline.beats_heading"), { "mbHeading" }, { tmargin = 10 })
    local beats = parse.beats or {}
    local spans = S.RootSpans(session)
    local hasEncounter = false
    for i, beat in ipairs(beats) do
        local index = i
        if beat.kind == "encounter" then
            hasEncounter = true
        end
        local tools = {}
        if not beat.implicit and spans[i] ~= nil then
            if i > 1 then
                tools[#tools + 1] = TinyButton("^", T("author.script_builder.outline.move_earlier_tooltip"), function() S.MoveBeat(ctx, index, -1) end)
            end
            if i < #beats then
                tools[#tools + 1] = TinyButton("v", T("author.script_builder.outline.move_later_tooltip"), function() S.MoveBeat(ctx, index, 1) end)
            end
        end
        local problems = 0
        if (beat.line or 0) > 0 then
            problems = #Problems(session, beat.line, 1)
        end
        children[#children + 1] = Card(ctx, { kind = "beat", index = index }, KIND_COLOR[beat.kind] or "#b0b0b0",
            string.format("%d. %s", i, string.upper(BeatKindName(beat.kind))), S.BeatLabel(beat), S.BeatSummary(beat), problems, tools)
    end
    if #beats == 0 then
        children[#children + 1] = ctx.Label(T("author.script_builder.outline.no_beats"), { "mbSub" })
    end
    local addRow = {
        ctx.SmallButton(T("author.script_builder.outline.add_narrative"), function() S.AddBeat(ctx, "narrative") end),
        ctx.SmallButton(T("author.script_builder.outline.add_montage"), function() S.AddBeat(ctx, "montage") end),
    }
    if not hasEncounter then
        addRow[#addRow + 1] = ctx.SmallButton(T("author.script_builder.outline.add_encounter"), function() S.AddBeat(ctx, "encounter") end)
    end
    children[#children + 1] = ctx.Row(addRow, { fit = true, tmargin = 4 })
    children[#children + 1] = ctx.Label(T("author.script_builder.outline.add_help"), { "mbSub" })

    --after the adventure.
    children[#children + 1] = ctx.Label(T("author.script_builder.outline.after_heading"), { "mbHeading" }, { tmargin = 10 })
    local missing = {}
    for _, key in ipairs({ "conclusion", "defeat" }) do
        local st = story[key]
        if st ~= nil then
            children[#children + 1] = Card(ctx, { kind = "story", key = key }, KIND_COLOR.story, T("author.script_builder.outline.story_kind"), STORY[key].title,
                string.sub(st.text or "", 1, 80), #Problems(session, st.line, 1), {})
        else
            local k = key
            missing[#missing + 1] = ctx.SmallButton(T("author.script_builder.outline.add_story", { title = STORY[key].title }), function() ctx.Do(function() S.AddStory(ctx, k) end) end)
        end
    end
    if #missing > 0 then
        children[#children + 1] = ctx.Row(missing, { fit = true })
    end
    return children
end

--- the editors (right) -----------------------------------------------------------------

local function OpenInJournal(ctx, line)
    local docid = E.Source(ctx.session.parse, line)
    local doc = DocsTable()[docid]
    ctx.close()
    if doc ~= nil then
        doc:ShowDocument{}
    end
end


--- the combat Encounter Builder for an [[encounter]] island ---------------------------

--The document and data key of the [[encounter]] island on expanded line
--`line` (the journal keys repeated tags by order: "encounter",
--"encounter-1", ...). nil when that line holds no such tag.
local function IslandKey(session, line)
    local docid, at = E.Source(session.parse, line)
    if docid == nil then
        return nil
    end
    for _, o in ipairs(E.TagOccurrences(E.Split(session.texts[docid] or "").lines)) do
        if o.line == at and lower(string.match(o.name, "^[^:]*") or "") == "encounter" then
            return docid, o.key
        end
    end
    return nil
end

--The encounter an island holds, or nil when it has none saved yet.
local function IslandEncounter(session, line)
    local docid, key = IslandKey(session, line)
    local doc = docid ~= nil and DocsTable()[docid] or nil
    local result = nil
    if doc ~= nil then
        pcall(function()
            local tag = (doc:try_get("annotations") or {})[key]
            if tag ~= nil then
                result = tag:try_get("encounter")
            end
        end)
    end
    return result
end

--One line about an island's monsters: who, and the encounter value.
local function IslandSummary(session, line)
    local encounter = IslandEncounter(session, line)
    if encounter == nil then
        return T("author.script_builder.encounter.no_monsters")
    end
    local text, ev = nil, nil
    pcall(function() text = encounter:Describe() end)
    pcall(function() ev = encounter:CountEDS() end)
    --one line: the description's lines joined, no separator left dangling.
    text = (string.gsub(trim(tostring(text or "")), "%s*[\r\n]+%s*", "; "))
    if text == "" then
        text = T("author.script_builder.encounter.no_monsters")
    end
    if ev ~= nil and ev > 0 then
        text = T("author.script_builder.encounter.monsters_with_ev", { monsters = text, ev = ev })
    end
    return text
end

--Open the combat Encounter Builder (the same one the journal island's
--settings button opens) on the island at expanded line `line`. This window
--closes so the map is free for staging monsters; every Save in the
--Encounter Builder writes the encounter back into the script document under
--the island's key. Reopen the Encounter Builder from the Game menu after.
function S.OpenCombatBuilder(ctx, line)
    local session = ctx.session
    local docid, key = IslandKey(session, line)
    if docid == nil or key == nil then
        session.status = T("author.script_builder.status.island_not_found")
        ctx.Refresh()
        return
    end
    ctx.close()
    --after this window's own uploads land (an island just added).
    dmhub.Schedule(0.5, function()
        if mod.unloaded then
            return
        end
        local doc = DocsTable()[docid]
        if doc == nil then
            return
        end
        local existing = nil
        pcall(function() existing = (doc:try_get("annotations") or {})[key] end)
        --work on a copy: it only reaches the document when Save is pressed.
        local tag = existing ~= nil and DeepCopy(existing) or RichEncounter.Create()
        tag.encounter:CreateEditorDialog{
            mode = "Save",
            journal = true,
            save = function()
                local live = DocsTable()[docid]
                if live == nil then
                    return
                end
                --script documents are journal (markdown) documents.
                ---@cast live MarkdownDocument
                local original = DeepCopy(live)
                local annotations = live:try_get("annotations") or {}
                annotations[key] = DeepCopy(tag)
                live.annotations = annotations
                live:Upload(original)
            end,
        }
    end)
end

--The "Open Combat Encounter Builder" button for the island on expanded line
--`line`; with no line, `addIsland()` writes the [[encounter]] tag first and
--returns the new island's line.
local function CombatBuilderButton(ctx, line, addIsland)
    return gui.Button{
        classes = { "sizeS" },
        width = "auto",
        height = 30,
        hpad = 14,
        borderBox = true,
        text = T("author.script_builder.encounter.open_combat_builder"),
        hover = gui.Tooltip(T("author.script_builder.encounter.open_combat_builder_tooltip")),
        click = function()
            local target = line
            if target == nil and addIsland ~= nil then
                ctx.Do(function() target = addIsland() end)
            end
            if target ~= nil then
                S.OpenCombatBuilder(ctx, target)
            end
        end,
    }
end

--`skip` = { [message] = true }: already shown further in (a reinforcement's own).
local function ProblemLabels(ctx, line, level, children, skip)
    for _, w in ipairs(Problems(ctx.session, line, level)) do
        if skip == nil or not skip[w.message] then
            children[#children + 1] = ctx.Label(w.message, { "mbProblem" })
        end
    end
end

function S.FeaturesEditor(ctx)
    local session = ctx.session
    local children = { ctx.Label(T("author.script_builder.features.heading"), { "mbHeading" }, { color = KIND_COLOR.features }) }
    children[#children + 1] = ctx.Label(T("author.script_builder.features.intro"), { "mbSub" })
    local unlocked = EncounterScript.UnlockedFeatures(session.parse)
    local unlocks = S.Unlocks(session)
    local keys = {}
    for k in pairs(EncounterScript.FEATURES) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local feature = EncounterScript.FEATURES[key]
        local on = unlocked[key] == true
        local section = {
            gui.Check{
                classes = { "sizeXs" },
                fontSize = 16,
                width = 400,
                height = 26,
                text = feature.name,
                value = on,
                change = function(element)
                    ctx.Do(function() S.SetFeature(ctx, feature, element.value == true) end)
                end,
            },
            ctx.Label(T("author.script_builder.features.turns_on", { summary = feature.summary }), { "mbSub" }),
        }
        if on then
            for _, u in ipairs(unlocks) do
                if u.feature == key then
                    local where = S.BeatLabel(u.beat)
                    if u.section ~= nil then
                        where = T("author.script_builder.features.where_scene", { scene = u.section.name, beat = where })
                    end
                    section[#section + 1] = ctx.Label(T("author.script_builder.features.on_explained", { where = where }), { "mbRule" }, { color = ON_COLOR })
                end
            end
            if key == "intelligence" then
                local grants = S.IntelligenceGrants(session)
                if grants == 0 then
                    section[#section + 1] = ctx.Label(T("author.script_builder.features.intelligence_none"), { "mbProblem" })
                else
                    section[#section + 1] = ctx.Label(TP("author.script_builder.features.intelligence_grants", grants), { "mbSub" })
                end
            end
            section[#section + 1] = ctx.Label(T("author.script_builder.features.party_told", { explanation = tostring(feature.explanation or "") }), { "mbSub" })
        else
            section[#section + 1] = ctx.Label(T("author.script_builder.features.off_help", { feature = feature.name }), { "mbSub" })
            if key == "intelligence" and S.IntelligenceGrants(session) > 0 then
                section[#section + 1] = ctx.Label(T("author.script_builder.features.intelligence_off"), { "mbProblem" })
            end
        end
        children[#children + 1] = gui.Panel{ classes = { "mbSection" }, children = section }
    end
    return children
end

function S.StoryEditor(ctx, key)
    local session = ctx.session
    local parse = session.parse
    local st = (parse.story or {})[key]
    local info = STORY[key]
    local children = { ctx.Label(string.upper(info.title), { "mbHeading" }, { color = KIND_COLOR.story }) }
    children[#children + 1] = ctx.Label(info.note, { "mbSub" })
    if st == nil then
        children[#children + 1] = ctx.Row({ ctx.SmallButton(T("author.script_builder.story.add_button"), function() ctx.Do(function() S.AddStory(ctx, key) end) end) }, { fit = true })
        return children
    end
    children[#children + 1] = ctx.TextBox(st.text, function(text)
        ctx.Commit(T("author.script_builder.status.edited_story", { title = info.title }), E.SetProse(parse, session.texts, st.textLines, st.line, text))
    end, { multiline = true, minHeight = 120, maxHeight = 500, placeholder = info.starter })
    if st.sceneTag ~= nil then
        children[#children + 1] = ctx.Label(T("author.script_builder.story.backdrop"), { "mbSub" })
    end
    ProblemLabels(ctx, st.line, 1, children)
    children[#children + 1] = ctx.Row({
        ctx.SmallButton(T("author.script_builder.story.open_in_journal"), function() OpenInJournal(ctx, st.line) end),
        ctx.ConfirmButton(T("author.script_builder.story.delete_button"), function()
            session.scriptSelected = nil
            ctx.Commit(T("author.script_builder.status.deleted_story", { title = info.title }), E.DeleteElement(parse, session.texts, st.line, 1), nil, { keepTags = true })
        end),
    }, { fit = true, tmargin = 8 })
    return children
end

--A narrative option's rules: one outcome editor per "|" line.
local function NarrativeRules(ctx, o, children)
    local session = ctx.session
    local parse = session.parse
    local lines = o.ruleLines or {}
    if #lines == 0 then
        children[#children + 1] = ctx.OutcomeEditor("", function(text)
            if trim(text) ~= "" then
                ctx.Commit(T("author.script_builder.status.added_choice_rule"), E.InsertAfterElement(parse, session.texts, o.line, 3, { "|" .. E.LineText(text) }))
            end
        end, nil, { placeholder = T("author.script_builder.narrative.choice_rule_placeholder") })
        return
    end
    for _, l in ipairs(lines) do
        local lineNo = l
        local docid, at = E.Source(parse, lineNo)
        local raw = E.Split(session.texts[docid] or "").lines[at] or ""
        local lead = string.match(raw, "^(%s*)") or ""
        local text = trim((string.gsub(string.gsub(raw, "^%s*|", ""), "|%s*$", "")))
        children[#children + 1] = ctx.OutcomeEditor(text, function(newText)
            if trim(newText) == "" then
                ctx.Commit(T("author.script_builder.status.removed_choice_rule"), E.DeleteLine(parse, lineNo))
            else
                ctx.Commit(T("author.script_builder.status.edited_choice_rule"), E.SetLine(parse, lineNo, lead .. "|" .. E.LineText(newText)))
            end
        end, nil, { placeholder = T("author.script_builder.narrative.choice_rule_placeholder") })
    end
end

function S.NarrativeEditor(ctx, beat, index)
    local session = ctx.session
    local parse = session.parse
    local children = { ctx.Label(string.upper(S.BeatLabel(beat)), { "mbHeading" }, { color = KIND_COLOR.narrative }) }
    children[#children + 1] = ctx.Label(T("author.script_builder.narrative.intro_help"), { "mbSub" })
    children[#children + 1] = ctx.Label(T("author.script_builder.narrative.intro_label"), { "mbFieldLabel" })
    children[#children + 1] = ctx.TextBox(beat.intro, function(text)
        ctx.Commit(T("author.script_builder.status.edited_narrative_intro"), E.SetProse(parse, session.texts, beat.introLines, beat.line, text))
    end, { multiline = true, placeholder = T("author.script_builder.narrative.intro_placeholder") })
    for _, u in ipairs(beat.unlocks or {}) do
        children[#children + 1] = ctx.Label(T("author.script_builder.narrative.turns_on_beat", { feature = u.name }), { "mbRule" }, { color = ON_COLOR })
    end
    if beat.sceneTag ~= nil then
        children[#children + 1] = ctx.Label(T("author.script_builder.narrative.backdrop"), { "mbSub" })
    end

    for si, sec in ipairs(beat.sections or {}) do
        local s = sec
        local options = RealOptions(s)
        local sc = {}
        sc[#sc + 1] = ctx.Row({
            gui.Label{ classes = { "mbHeading" }, color = KIND_COLOR.narrative, width = "auto", height = "auto", valign = "center", rmargin = 8,
                text = T("author.script_builder.narrative.scene_heading", { number = si }) },
            ctx.TextBox(s.name, function(text)
                text = (string.gsub(E.LineText(text), "^#+%s*", ""))
                if text ~= "" then
                    ctx.Commit(T("author.script_builder.status.renamed_scene"), E.SetLine(parse, s.line, "## " .. text))
                end
            end, { width = 320, height = 28 }),
        }, { fit = true })
        sc[#sc + 1] = ctx.Label(T("author.script_builder.narrative.scene_text_label"), { "mbFieldLabel" })
        sc[#sc + 1] = ctx.TextBox(s.text, function(text)
            ctx.Commit(T("author.script_builder.status.edited_scene_text"), E.SetProse(parse, session.texts, s.textLines, s.line, text))
        end, { multiline = true, placeholder = T("author.script_builder.narrative.scene_text_placeholder") })
        for _, u in ipairs(s.unlocks or {}) do
            sc[#sc + 1] = ctx.Label(T("author.script_builder.narrative.turns_on_scene", { feature = u.name }), { "mbRule" }, { color = ON_COLOR })
        end

        --who chooses, and the question.
        local function WriteMode(mode, prompt)
            local line = E.NarrativeModeLine(mode, prompt)
            local spans = s.promptLines
            if spans ~= nil and #spans > 0 then
                ctx.Commit(T("author.script_builder.status.edited_scene_choice"), One(E.PatchExpanded(parse, spans[1][1], spans[#spans][2], { line })))
            else
                local after = s.line
                for _, span in ipairs(s.textLines or {}) do
                    after = math.max(after, span[2])
                end
                ctx.Commit(T("author.script_builder.status.edited_scene_choice"), One(E.InsertBlockAfter(parse, session.texts, after, { line })))
            end
        end
        if #options > 0 then
            sc[#sc + 1] = ctx.Label(T("author.script_builder.narrative.choice_label"), { "mbFieldLabel" })
            sc[#sc + 1] = ctx.Row({
                ctx.PickDropdown({
                    { id = "together", text = T("author.script_builder.narrative.mode_together") },
                    { id = "individual", text = T("author.script_builder.narrative.mode_individual") },
                }, s.mode, function(id) WriteMode(id, s.prompt) end, { width = 260, lmargin = 0,
                    tooltip = T("author.script_builder.narrative.mode_tooltip") }),
                ctx.TextBox(s.prompt, function(text) WriteMode(s.mode, text) end, { width = 420, height = 24, placeholder = T("author.script_builder.narrative.prompt_placeholder") }),
            }, { fit = true })
            if not s.modeExplicit and #options >= 2 then
                sc[#sc + 1] = ctx.Label(T("author.script_builder.narrative.mode_implicit"), { "mbSub" })
            end
        else
            sc[#sc + 1] = ctx.Label(T("author.script_builder.narrative.no_choices"), { "mbSub" })
        end

        for oi, opt in ipairs(options) do
            local o = opt
            local oc = {}
            oc[#oc + 1] = ctx.Row({
                gui.Label{ classes = { "mbSub" }, bold = true, width = "auto", height = "auto", valign = "center", rmargin = 8, text = T("author.script_builder.narrative.choice_heading", { number = oi }) },
                ctx.TextBox(o.name, function(text)
                    text = (string.gsub(E.LineText(text), "^#+%s*", ""))
                    if text ~= "" then
                        ctx.Commit(T("author.script_builder.status.renamed_choice"), E.SetLine(parse, o.line, E.OptionHeadingLine(text)))
                    end
                end, { width = 320, height = 26 }),
                ctx.ConfirmButton(T("author.script_builder.narrative.delete_choice_button"), function()
                    ctx.Commit(T("author.script_builder.status.deleted_choice", { choice = o.name }), E.DeleteElement(parse, session.texts, o.line, 3), nil, { keepTags = true })
                end),
            }, { fit = true })
            oc[#oc + 1] = ctx.TextBox(o.text, function(text)
                ctx.Commit(T("author.script_builder.status.edited_choice_text"), E.SetProse(parse, session.texts, o.textLines, o.line, text))
            end, { multiline = true, minHeight = 26, placeholder = T("author.script_builder.narrative.choice_text_placeholder") })
            NarrativeRules(ctx, o, oc)
            sc[#sc + 1] = gui.Panel{ classes = { "mbSection" }, children = oc }
        end

        sc[#sc + 1] = ctx.Row({
            ctx.SmallButton(T("author.script_builder.narrative.add_choice"), function()
                local last = options[#options]
                if last ~= nil then
                    ctx.Commit(T("author.script_builder.status.added_choice"), E.InsertAfterElement(parse, session.texts, last.line, 3, E.OptionBlock("New choice", "", {})))
                else
                    ctx.Commit(T("author.script_builder.status.added_choice"), E.InsertAfterElement(parse, session.texts, s.line, 2,
                        { E.NarrativeModeLine("together", "What do you do?"), "", E.OptionHeadingLine("New choice") }))
                end
            end),
            ctx.ConfirmButton(T("author.script_builder.narrative.delete_scene"), function()
                ctx.Commit(T("author.script_builder.status.deleted_scene", { scene = s.name }), E.DeleteElement(parse, session.texts, s.line, 2), nil, { keepTags = true })
            end),
        }, { fit = true, tmargin = 4 })
        children[#children + 1] = gui.Panel{ classes = { "mbSection" }, children = sc }
    end

    ProblemLabels(ctx, beat.line, 1, children)
    children[#children + 1] = ctx.Row({
        ctx.SmallButton(T("author.script_builder.narrative.add_scene"), function()
            local last = beat.sections ~= nil and beat.sections[#beat.sections] or nil
            if last ~= nil then
                ctx.Commit(T("author.script_builder.status.added_scene"), E.InsertAfterElement(parse, session.texts, last.line, 2, E.NarrativeSectionBlock("New Scene")))
            else
                ctx.Commit(T("author.script_builder.status.added_scene"), E.InsertAfterElement(parse, session.texts, beat.line, 1, E.NarrativeSectionBlock("New Scene")))
            end
        end),
        ctx.SmallButton(T("author.script_builder.narrative.open_in_journal"), function() OpenInJournal(ctx, beat.line) end),
        ctx.ConfirmButton(T("author.script_builder.narrative.delete_button"), function() ctx.Do(function() S.DeleteBeat(ctx, index) end) end),
    }, { fit = true, tmargin = 8 })
    return children
end

function S.MontageEditor(ctx, beat, index)
    local children = { ctx.Label(T("author.script_builder.montage.heading"), { "mbHeading" }, { color = KIND_COLOR.montage }) }
    children[#children + 1] = ctx.Label(T("author.script_builder.montage.intro"), { "mbSub" })
    children[#children + 1] = ctx.Row({
        gui.Button{
            classes = { "sizeS" },
            width = "auto",
            height = 34,
            hpad = 16,
            borderBox = true,
            text = T("author.script_builder.montage.open_builder"),
            click = function()
                ctx.OpenMontage(beat)
            end,
        },
    }, { fit = true, vmargin = 8 })
    if trim(beat.intro or "") ~= "" then
        children[#children + 1] = ctx.Label(beat.intro, { "mbSub" })
    end
    for _, r in ipairs(beat.rounds or {}) do
        local names = {}
        for _, e in ipairs(r.entries or {}) do
            names[#names + 1] = e.name
        end
        children[#children + 1] = ctx.Label(T("author.script_builder.montage.round_line", { number = tostring(r.number), entries = cond(#names == 0, T("author.script_builder.montage.round_empty"), table.concat(names, ", ")) }), { "mbSub" })
    end
    ProblemLabels(ctx, beat.line, 1, children)
    children[#children + 1] = ctx.Row({
        ctx.SmallButton(T("author.script_builder.montage.open_in_journal"), function() OpenInJournal(ctx, beat.line) end),
        ctx.ConfirmButton(T("author.script_builder.montage.delete_button"), function() ctx.Do(function() S.DeleteBeat(ctx, index) end) end),
    }, { fit = true, tmargin = 8 })
    return children
end

--- the encounter --------------------------------------------------------------------------

local SETUP_KINDS = {
    { id = "placeobjects", text = T("author.script_builder.setup.kind_placeobjects") },
    { id = "bystanders", text = T("author.script_builder.setup.kind_bystanders") },
    { id = "victory", text = T("author.script_builder.setup.kind_victory") },
}

local function Numbers(lo, hi)
    local options = {}
    for n = lo, hi do
        options[#options + 1] = { id = tostring(n), text = tostring(n) }
    end
    return options
end

--A new setup instruction of `kind`, using names from this map where it has them.
local function NewSetup(kind)
    local lists = EncounterMontageBuilder.Lists()
    if kind == "bystanders" then
        return { kind = "bystanders", label = "Bystanders", names = { "Civilian" } }
    elseif kind == "victory" then
        return { kind = "victory" }
    end
    local zone = "trap"
    for _, z in ipairs(lists.zones) do
        if lower(z) == "trap" then
            zone = "trap"
            break
        end
        zone = lower(z)
    end
    return { kind = "placeobjects", label = "Trap", qty = 2, object = lists.objects[1] or "Snare Trap", zone = zone, deleteOthers = true }
end

local function SetupRow(ctx, ins)
    local session = ctx.session
    local parse = session.parse
    local lists = EncounterMontageBuilder.Lists()
    local function Write(newIns)
        ctx.Commit(T("author.script_builder.status.edited_setup"), E.SetLine(parse, ins.line, E.SetupLine(newIns)))
    end
    local function Copy()
        local c = {}
        for k, v in pairs(ins) do c[k] = v end
        return c
    end
    ---@type Panel[]
    local row = {}
    if ins.kind == "placeobjects" then
        row[#row + 1] = ctx.TextBox(ins.label, function(text)
            local c = Copy()
            c.label = (string.gsub(E.LineText(text), ":", ""))
            Write(c)
        end, { width = 90, height = 24 })
        row[#row + 1] = ctx.Word(T("author.script_builder.setup.place"))
        row[#row + 1] = ctx.PickDropdown(Numbers(1, 12), tostring(ins.qty), function(id)
            local c = Copy()
            c.qty = tonumber(id)
            Write(c)
        end, { width = 56 })
        if #lists.objects > 0 then
            local options, chosen = ctx.NameOptions(lists.objects, ins.object)
            row[#row + 1] = ctx.PickDropdown(options, chosen, function(id)
                local c = Copy()
                c.object = id
                Write(c)
            end, { width = 190, menuWidth = 260, search = true, tooltip = T("author.script_builder.setup.object_tooltip") })
        else
            row[#row + 1] = ctx.TextBox(ins.object, function(text)
                local c = Copy()
                c.object = E.LineText(text)
                Write(c)
            end, { width = 160, height = 24 })
        end
        row[#row + 1] = ctx.Word(T("author.script_builder.setup.objects_in"))
        local zoneOptions, zoneChosen = ctx.NameOptions(lists.zones, ins.zone)
        row[#row + 1] = ctx.PickDropdown(zoneOptions, zoneChosen, function(id)
            local c = Copy()
            c.zone = lower(id)
            Write(c)
        end, { width = 130 })
        row[#row + 1] = ctx.Word(T("author.script_builder.setup.zones"))
        row[#row + 1] = gui.Check{
            classes = { "sizeXs" },
            width = 230,
            height = 24,
            valign = "center",
            text = T("author.script_builder.setup.delete_others"),
            value = ins.deleteOthers == true,
            hover = gui.Tooltip(T("author.script_builder.setup.delete_others_tooltip")),
            change = function(element)
                local c = Copy()
                c.deleteOthers = element.value == true
                Write(c)
            end,
        }
    elseif ins.kind == "bystanders" then
        row[#row + 1] = ctx.TextBox(ins.label, function(text)
            local c = Copy()
            c.label = (string.gsub(E.LineText(text), ":", ""))
            Write(c)
        end, { width = 110, height = 24 })
        row[#row + 1] = ctx.TextBox(table.concat(ins.names or {}, ", "), function(text)
            local c = Copy()
            c.names = {}
            for part in string.gmatch(E.LineText(text), "[^,]+") do
                if trim(part) ~= "" then
                    c.names[#c.names + 1] = trim(part)
                end
            end
            if #c.names > 0 then
                Write(c)
            end
        end, { width = 260, height = 24, placeholder = T("author.script_builder.setup.bystander_names_placeholder") })
        row[#row + 1] = ctx.Word(T("author.script_builder.setup.bystanders_rest"))
    elseif ins.kind == "victory" then
        row[#row + 1] = ctx.Word(T("author.script_builder.setup.victory_start"))
        local options, chosen = ctx.NameOptions(lists.keywords, ins.who ~= nil and (ins.whoText or ins.who) or nil, { { id = "", text = T("author.script_builder.setup.victory_enemy") } })
        row[#row + 1] = ctx.PickDropdown(options, chosen or "", function(id)
            Write({ kind = "victory", who = cond(id == "", nil, lower(id)), whoText = cond(id == "", nil, id) })
        end, { width = 160, menuWidth = 220, search = true })
        row[#row + 1] = ctx.Word(T("author.script_builder.setup.victory_end"))
    else
        local docid, at = E.Source(parse, ins.line)
        row[#row + 1] = ctx.TextBox(E.Split(session.texts[docid] or "").lines[at] or "", function(text)
            ctx.Commit(T("author.script_builder.status.edited_setup"), E.SetLine(parse, ins.line, E.LineText(text)))
        end, { width = 520, height = 24 })
    end
    row[#row + 1] = gui.Button{ classes = { "sizeXs" }, width = 22, height = 22, lmargin = 6, valign = "center", text = "x",
        hover = gui.Tooltip(T("author.script_builder.setup.remove_tooltip")),
        click = function()
            ctx.Commit(T("author.script_builder.status.removed_setup"), E.DeleteLine(parse, ins.line))
        end }
    return ctx.Row(row, { fit = true, vmargin = 2 })
end

--The "Arrive:" form of a reinforcement group.
local function ScheduleRow(ctx, r)
    local session = ctx.session
    local parse = session.parse
    local schedule = r.schedule or { rounds = { [3] = true } }
    local function Write(newSchedule)
        local line = E.ArriveLine(newSchedule)
        if r.scheduleLine ~= nil then
            ctx.Commit(T("author.script_builder.status.edited_arrive"), E.SetLine(parse, r.scheduleLine, line))
        else
            ctx.Commit(T("author.script_builder.status.set_arrive"), One(E.InsertBlockAfter(parse, session.texts, r.line, { line })))
        end
    end
    local mode = cond(schedule.rounds ~= nil, "rounds", "every")
    ---@type Panel[]
    local row = {
        ctx.Word(T("author.script_builder.reinforcements.arrive"), { hmargin = 0 }),
        ctx.PickDropdown({ { id = "rounds", text = T("author.script_builder.reinforcements.mode_rounds") }, { id = "every", text = T("author.script_builder.reinforcements.mode_every") } }, mode, function(id)
            if id == "rounds" then
                Write({ rounds = { [3] = true } })
            else
                Write({ every = 2, from = 2 })
            end
        end, { width = 150 }),
    }
    if mode == "rounds" then
        local list = {}
        for n in pairs(schedule.rounds or {}) do
            list[#list + 1] = n
        end
        table.sort(list)
        local parts = {}
        for i, n in ipairs(list) do
            parts[i] = tostring(n)
        end
        row[#row + 1] = ctx.TextBox(table.concat(parts, ", "), function(text)
            local rounds, any = {}, false
            for n in string.gmatch(text or "", "%d+") do
                rounds[tonumber(n)] = true
                any = true
            end
            if any then
                Write({ rounds = rounds })
            end
        end, { width = 120, height = 24, placeholder = T("author.script_builder.reinforcements.rounds_placeholder") })
    else
        row[#row + 1] = ctx.Word(T("author.script_builder.reinforcements.every"))
        row[#row + 1] = ctx.PickDropdown(Numbers(1, 5), tostring(schedule.every or 1), function(id)
            Write({ every = tonumber(id), from = schedule.from, to = schedule.to })
        end, { width = 56 })
        row[#row + 1] = ctx.Word(T("author.script_builder.reinforcements.rounds_from"))
        row[#row + 1] = ctx.PickDropdown(Numbers(1, 10), tostring(schedule.from or 1), function(id)
            Write({ every = schedule.every, from = tonumber(id), to = schedule.to })
        end, { width = 56 })
        local untilOptions = { { id = "", text = T("author.script_builder.reinforcements.until_none") } }
        for _, o in ipairs(Numbers(1, 12)) do
            untilOptions[#untilOptions + 1] = { id = o.id, text = T("author.script_builder.reinforcements.until_round", { round = o.text }) }
        end
        row[#row + 1] = ctx.PickDropdown(untilOptions, schedule.to ~= nil and tostring(schedule.to) or "", function(id)
            Write({ every = schedule.every, from = schedule.from, to = tonumber(id) })
        end, { width = 96 })
    end
    if r.schedule == nil then
        row[#row + 1] = ctx.Word(T("author.script_builder.reinforcements.never_arrive"), { color = PROBLEM_COLOR })
    end
    return ctx.Row(row, { fit = true, vmargin = 2 })
end

local function ReinforcementEditor(ctx, r)
    local session = ctx.session
    local parse = session.parse
    local lists = EncounterMontageBuilder.Lists()
    local rc = {}
    rc[#rc + 1] = ctx.Row({
        gui.Label{ classes = { "mbHeading" }, color = KIND_COLOR.encounter, width = "auto", height = "auto", valign = "center", rmargin = 8, text = T("author.script_builder.reinforcements.heading") },
        ctx.TextBox(r.name, function(text)
            text = E.LineText(text)
            if text ~= "" then
                ctx.Commit(T("author.script_builder.status.renamed_reinforcements"), E.SetLine(parse, r.line, "## Reinforcements: " .. text))
            end
        end, { width = 280, height = 28 }),
    }, { fit = true })
    rc[#rc + 1] = ScheduleRow(ctx, r)

    --where they come in.
    local zoneOptions, zoneChosen = ctx.NameOptions(lists.zones, r.zone, { { id = "", text = T("author.script_builder.reinforcements.enter_where_placed") } })
    rc[#rc + 1] = ctx.Row({
        ctx.Word(T("author.script_builder.reinforcements.enter"), { hmargin = 0 }),
        ctx.PickDropdown(zoneOptions, zoneChosen or "", function(id)
            if id == "" then
                if r.zoneLine ~= nil then
                    ctx.Commit(T("author.script_builder.status.enter_where_placed"), E.DeleteLine(parse, r.zoneLine))
                end
            elseif r.zoneLine ~= nil then
                ctx.Commit(T("author.script_builder.status.changed_enter"), E.SetLine(parse, r.zoneLine, E.EnterLine(id)))
            else
                ctx.Commit(T("author.script_builder.status.set_enter"), One(E.InsertBlockAfter(parse, session.texts, r.scheduleLine or r.line, { E.EnterLine(id) })))
            end
        end, { width = 240, tooltip = T("author.script_builder.reinforcements.enter_tooltip") }),
    }, { fit = true, vmargin = 2 })

    --what they shout as they arrive.
    for _, sh in ipairs(r.shoutLines or {}) do
        local shout = sh
        rc[#rc + 1] = ctx.Row({
            ctx.Word(T("author.script_builder.reinforcements.shout"), { hmargin = 0 }),
            ctx.TextBox(shout.text, function(text)
                if trim(text) == "" then
                    ctx.Commit(T("author.script_builder.status.removed_shout"), E.DeleteLine(parse, shout.line))
                else
                    ctx.Commit(T("author.script_builder.status.edited_shout"), E.SetLine(parse, shout.line, E.ShoutLine(text)))
                end
            end, { width = 420, height = 24 }),
            gui.Button{ classes = { "sizeXs" }, width = 22, height = 22, lmargin = 6, valign = "center", text = "x",
                click = function() ctx.Commit(T("author.script_builder.status.removed_shout"), E.DeleteLine(parse, shout.line)) end },
        }, { fit = true, vmargin = 1 })
    end

    --the groups that come, one per arrival, in turn.
    local groups = #(r.islands or {})
    if groups == 0 then
        rc[#rc + 1] = ctx.Label(T("author.script_builder.reinforcements.no_groups"), { "mbProblem" })
    end
    for gi, island in ipairs(r.islands or {}) do
        rc[#rc + 1] = ctx.Label(cond(groups > 1, T("author.script_builder.reinforcements.group_cycle", { number = gi, first = gi, second = gi + groups, monsters = IslandSummary(session, island.line) }),
            T("author.script_builder.reinforcements.group", { number = gi, monsters = IslandSummary(session, island.line) })), { "mbSub" }, { tmargin = 4 })
        rc[#rc + 1] = ctx.Row({ CombatBuilderButton(ctx, island.line) }, { fit = true })
    end
    ProblemLabels(ctx, r.line, 2, rc)
    rc[#rc + 1] = ctx.Row({
        ctx.SmallButton(T("author.script_builder.reinforcements.add_shout"), function()
            local after = r.line
            if r.shoutLines ~= nil and #r.shoutLines > 0 then
                after = r.shoutLines[#r.shoutLines].line
            elseif r.zoneLine ~= nil or r.scheduleLine ~= nil then
                after = math.max(r.zoneLine or 0, r.scheduleLine or 0)
            end
            ctx.Commit(T("author.script_builder.status.added_shout"), One(E.InsertBlockAfter(parse, session.texts, after, { E.ShoutLine("Here they come!") })))
        end),
        ctx.SmallButton(T("author.script_builder.reinforcements.add_group"), function()
            local after = r.line
            for _, island in ipairs(r.islands or {}) do
                after = math.max(after, island.line)
            end
            ctx.Commit(T("author.script_builder.status.added_group"), One(E.InsertBlockAfter(parse, session.texts, after, { "[[encounter]]" })), nil, { keepTags = true })
        end),
        ctx.ConfirmButton(T("author.script_builder.reinforcements.delete_button"), function()
            ctx.Commit(T("author.script_builder.status.deleted_reinforcements", { name = r.name }), E.DeleteElement(parse, session.texts, r.line, 2), nil, { keepTags = true })
        end),
    }, { fit = true, tmargin = 4 })
    return gui.Panel{ classes = { "mbSection" }, children = rc }
end

function S.EncounterEditor(ctx, beat, index)
    local session = ctx.session
    local parse = session.parse
    local children = { ctx.Label(T("author.script_builder.encounter.heading"), { "mbHeading" }, { color = KIND_COLOR.encounter }) }
    children[#children + 1] = ctx.Label(T("author.script_builder.encounter.intro"), { "mbSub" })

    --the monsters.
    local mc = { ctx.Label(T("author.script_builder.encounter.monsters_label"), { "mbFieldLabel" }) }
    if beat.encounterTag ~= nil then
        mc[#mc + 1] = ctx.Label(IslandSummary(session, beat.encounterLine), { "mbSub" })
        mc[#mc + 1] = ctx.Row({ CombatBuilderButton(ctx, beat.encounterLine) }, { fit = true, tmargin = 4 })
    else
        mc[#mc + 1] = ctx.Label(T("author.script_builder.encounter.no_monsters"), { "mbSub" })
        --the button writes the [[encounter]] tag the monsters are saved under.
        mc[#mc + 1] = ctx.Row({
            CombatBuilderButton(ctx, nil, function()
                if not EncounterMontageBuilder.Commit(session, T("author.script_builder.status.added_island"),
                    { E.InsertBlockAfter(parse, session.texts, beat.line, { "[[encounter]]" }) }, nil, { keepTags = true }) then
                    return nil
                end
                local updated = session.parse.beats[index]
                return updated ~= nil and updated.encounterLine or nil
            end),
        }, { fit = true, tmargin = 4 })
    end
    children[#children + 1] = gui.Panel{ classes = { "mbSection" }, children = mc }

    --setup lines.
    local sc = { ctx.Label(T("author.script_builder.setup.label"), { "mbFieldLabel" }) }
    for _, ins in ipairs(beat.setup or {}) do
        sc[#sc + 1] = SetupRow(ctx, ins)
    end
    if #(beat.setup or {}) == 0 then
        sc[#sc + 1] = ctx.Label(T("author.script_builder.setup.none"), { "mbSub" })
    end
    local addOptions = { { id = "", text = T("author.script_builder.setup.add") } }
    for _, k in ipairs(SETUP_KINDS) do
        addOptions[#addOptions + 1] = k
    end
    sc[#sc + 1] = gui.Dropdown{
        classes = { "sizeXs" },
        width = 260,
        height = 24,
        tmargin = 2,
        halign = "left",
        options = addOptions,
        idChosen = "",
        change = function(element)
            ---@cast element Dropdown
            local kind = element.idChosen
            if type(kind) ~= "string" or kind == "" then
                return
            end
            local after = beat.line
            for _, ins in ipairs(beat.setup or {}) do
                after = math.max(after, ins.line)
            end
            ctx.Commit(T("author.script_builder.status.added_setup"), One(E.InsertBlockAfter(parse, session.texts, after, { E.SetupLine(NewSetup(kind)) })))
        end,
    }
    sc[#sc + 1] = ctx.Label(T("author.script_builder.setup.help"), { "mbSub" })
    children[#children + 1] = gui.Panel{ classes = { "mbSection" }, children = sc }

    --reinforcements (each shows its own problems).
    local shown = {}
    for _, r in ipairs(beat.reinforcements or {}) do
        children[#children + 1] = ReinforcementEditor(ctx, r)
        for _, w in ipairs(Problems(session, r.line, 2)) do
            shown[w.message] = true
        end
    end

    ProblemLabels(ctx, beat.line, 1, children, shown)
    children[#children + 1] = ctx.Row({
        ctx.SmallButton(T("author.script_builder.encounter.add_reinforcements"), function()
            ctx.Commit(T("author.script_builder.status.added_reinforcements"), E.InsertAfterElement(parse, session.texts, beat.line, 1, E.ReinforcementBlock("New Arrivals")), nil, { keepTags = true })
        end),
        ctx.ConfirmButton(T("author.script_builder.encounter.delete_button"), function() ctx.Do(function() S.DeleteBeat(ctx, index) end) end),
    }, { fit = true, tmargin = 8 })
    return children
end

--- the editor for what is picked ---------------------------------------------------------

function S.Editor(ctx)
    local session = ctx.session
    local sel = session.scriptSelected
    if sel ~= nil and sel.kind == "features" then
        return S.FeaturesEditor(ctx)
    elseif sel ~= nil and sel.kind == "story" then
        return S.StoryEditor(ctx, sel.key)
    elseif sel ~= nil and sel.kind == "beat" then
        local beat = (session.parse.beats or {})[sel.index]
        if beat ~= nil then
            if beat.kind == "narrative" then
                return S.NarrativeEditor(ctx, beat, sel.index)
            elseif beat.kind == "montage" then
                return S.MontageEditor(ctx, beat, sel.index)
            elseif beat.kind == "encounter" then
                if beat.implicit then
                    return { ctx.Label(T("author.script_builder.encounter.implicit"), { "mbSub" }) }
                end
                return S.EncounterEditor(ctx, beat, sel.index)
            end
        end
    end
    return {
        ctx.Label(T("author.script_builder.editor.empty_heading"), { "mbHeading" }),
        ctx.Label(T("author.script_builder.editor.empty_help"), { "mbSub" }),
        ctx.Label(T("author.script_builder.editor.empty_undo"), { "mbSub" }),
    }
end

